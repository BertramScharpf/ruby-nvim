#
#  neovim/remote.rb  --  Remote access for Neovim
#

require "neovim/foreign/supplement"

require "neovim/logging"
require "neovim/connection"


module Neovim

  class Remote

    class Message

      @subs, @subh = [], {}

      class <<self

        def from_array ary
          kind, *payload = *ary
          klass = find kind
          klass or raise "No message type for id #{kind.inspect}"
          klass[ *payload]
        end

        def inherited cls ; @subs.push cls ; end
        def find id
          @subh[ id] ||= @subs.find { |c| c::ID == id }
        end

        alias [] new

      end

      def initialize *args
        z = self.class::KEYS.zip args
        @cont = z.inject Hash.new do |c,(h,k)| c[h] = k ; c end
      end

      def inspect
        "#<#{self.class.plain_name} #@cont>"
      end

      def to_s
        j = @cont.map { |k,v| "#{k}:#{v}" if v }.compact.join ","
        "#{self.class.plain_name}(#{j})"
      end

      def method_missing sym, *args
        if @cont.key? sym then @cont[ sym] else super end
      end

      def respond_to_missing? sym, priv = nil
        @cont.key? sym.to_sym
      end

      def methods *args
        super.concat @cont.keys
      end

      def to_h ; @cont ; end

      def fields ; @cont.fetch_values *self.class::KEYS ; end

      def to_a
        [self.class::ID, *fields]
      end

      class Request < Message
        ID = 0
        KEYS = %i(request_id method_name arguments)
      end

      class Response < Message
        ID = 1
        KEYS = %i(request_id error value)
        def initialize *args
          super
          e = @cont[ :error]
          if e and not Array === e then
            @cont[ :error] = [0, e]
          end
        end
      end

      class Notification < Message
        ID = 2
        KEYS = %i(method_name arguments)
      end

    end

    class ResponseError < StandardError ; end

    class Disconnected < RuntimeError ; end


    include Logging

    class <<self

      include Logging

      private :new

      def open_conn conntype, *args, **kwargs
        conntype.open_files *args, **kwargs do |conn|
          yield conn
        end
      end

      public

      def open conntype, *args, **kwargs
        open_conn conntype, *args, **kwargs do |conn|
          i = new nil, conn
          yield i
        end
      end

      def start plugins, *args
        open_logfile do
          log :info, "Starting", args: $*
          open_conn *args do |conn|
            i = new plugins, conn
            yield i
          end
        ensure
          log :info, "Leaving"
        end
      end

      def start_client *args
        start nil, *args do |i|
          yield i.start
        end
      end

    end

    def initialize plugins, conn
      @conn = conn
      @request_id = 0
      @responses = {}
      @plugins = {}
      @plugins.update plugins if plugins
    end

    def client_name
      l = @plugins.values.select { |p| p.type }
      if l.notempty? then
        l.map! { |p| p.type }
        l.uniq!
        name = l.join "-"
        log :info, "Client Name", name: name
        "ruby-#{name}-host"
      else
        "ruby-client"
      end
    end

    def client_type ; self.class.plain_name.downcase ; end

    def client_methods
      l = @plugins.values.reject { |p| p.type }
      if l.notempty? then
        r = {}
        l.each { |p| p.options { |name,opts| r[ name] = opts } }
        r
      end
    end


    def start
      @conn.start self
      @conn.client
    end

    def run until_id = nil
      loop do
        if @deferred and @conn.client then
          d, @deferred = @deferred, nil
          d.each { |p| p.call }
        end
        message = get
        case message
        when Message::Response then
          if @responses.key? message.request_id then
            @responses[ message.request_id] = message
          else
            log :warning, "Dropped response", message.request_id
          end
        when Message::Request, Message::Notification then
          h = find_handler message.method_name
          if h then
            p = proc do
              begin
                log :debug1, "Calling handler", name: message.method_name, args: message.arguments
                r = h.execute @conn.client, *message.arguments
                log :debug1, "Handler result", result: r
              rescue
                e = [ 0, $!.to_s]
                log_exception :error
              end
              put Message::Response[ message.request_id, e, r] if message.respond_to? :request_id
            end
            if @conn.client or not h.needs_client? then
              p.call
            else
              log :info, "Deferred handler for", name: message.method_name
              @deferred ||= []
              @deferred.push p
            end
          else
            if message.respond_to? :request_id then
              put Message::Response[ message.request_id, [0, "No handler #{message.method_name}."], nil]
            end
          end
        end
        break if until_id and @responses[ until_id]
      end
    end

    def request method, *args
      @request_id += 1
      put Message::Request[ @request_id, method, args]
      @responses[ @request_id] = nil
      run @request_id
      r = @responses.delete @request_id
      if r.error then
        t, e = *r.error
        t = @conn.error t
        raise ResponseError, "#{t}: #{e}"
      end
      r.value
    end

    def notify method, *args
      put Message::Notification[ method, args]
    end

    private

    def put msg
      log :debug2, "Sending Message", data: msg
      @conn.put msg.to_a
      self
    rescue Errno::EPIPE
      raise Disconnected, "Broken pipe on write"
    end

    def get
      IO.select [@conn.input], nil, nil
      raise Disconnected, "EOF on wait" if @conn.eof?
      msg = Message.from_array @conn.get
      log :debug2, "Received Message", data: msg
      msg
    rescue EOFError
      raise Disconnected, "EOF on read"
    end

    def find_handler name
      @plugins.each_value do |plugin|
        h = plugin.get_handler name
        if h then
          log :info, "Found handler", name: name
          return h
        end
      end
      log :error, "No handler found for #{name}."
      nil
    end

  end

end

