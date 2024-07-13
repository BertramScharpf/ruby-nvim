#
#  neovim/messager.rb  --  Send and Receive Messages
#

require "neovim/foreign/supplement"

require "neovim/logging"


module Neovim

  class Messager

    class Message

      @subs, @subh = [], {}

      class <<self

        def from_array ary
          kind, *payload = *ary
          klass = find kind
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
        c = self.class.name.sub /.*::/, ""
        "#<#{c} #@cont>"
      end

      def to_s
        c = self.class.name.sub /.*::/, ""
        j = @cont.map { |k,v| "#{k}:#{v}" if v }.compact.join ","
        "#{c}(#{j})"
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

    class Disconnected < RuntimeError
      def initialize
        super "Lost connection to nvim process"
      end
    end


    include Logging

    def initialize conn, session
      @conn, @session = conn, session
      @request_id = 0
      @responses = {}
    end

    def run until_id = nil
      loop do
        message = get
        case message
        when Message::Response then
          if @responses.key? message.request_id then
            @responses[ message.request_id] = message
          else
            log :warning, "Dropped response", message.request_id
          end
        when Message::Request then
          begin
            r = @session.execute_handler message.method_name, message.arguments
            log :debug1, "Request result", result: r
          rescue
            e = [ 0, $!.to_s]
            log_exception :error
          end
          rsp = Message::Response.new message.request_id, e, r
          put rsp
        when Message::Notification then
          begin
            @session.execute_handler message.method_name, message.arguments
          rescue
            log_exception :error
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
      log :debug1, "Sending Message", data: msg
      @conn.put msg.to_a
      self
    rescue Errno::EPIPE
      raise Disconnected
    end

    def get
      IO.select [@conn.input], nil, nil
      raise Disconnected if @conn.eof?
      msg = Message.from_array @conn.get
      log :debug1, "Received Message", data: msg
      msg
    rescue EOFError
      raise Disconnected
    end

  end

end

