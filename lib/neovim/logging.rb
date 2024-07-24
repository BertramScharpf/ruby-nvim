#
#  neovim/logging.rb  --  Logging facility
#

require "neovim/foreign/supplement"


module Neovim

  module Logging

    class Logger

      class <<self

        private :new

        SUBS = []

        def inherited cls
          SUBS.push cls
        end

        def provide str
          opened = nil
          args = str.to_s.split ":"
          args.each { |a| a.gsub! %r/%(\h\h)/ do ($1.to_i 0x10).chr end }
          cls =
            if args.first =~ /\A\w+\z/ then
              prot = args.shift
              (SUBS.find { |s| s::NAME == prot rescue nil }) or raise "Logger not found: #{str}"
            else
              Text
            end
          dest = args.shift
          cls.open dest, **(parse_arguments args) do |i|
            opened = true
            yield i
          end
        rescue  # Errno::EACCES, Errno::ENOENT
          raise unless not opened and str.notempty?
          $stderr.puts "Failed to open log file '#{str}'. Logging to stderr."
          str = nil
          retry
        end

        private

        def parse_arguments args
          r = {}
          args.each { |a|
            k, v = a.split "=", 2
            r[ k.to_sym] = parse_value v
          }
          r
        end

        def parse_value val
          if val.nil? then
            true
          elsif val =~ /\A(?:0x)?\d+\z/ then
            Integer val
          else
            case val.downcase
            when "true", "yes", "on"  then true
            when "false", "no", "off" then false
            else                           val.notempty?
            end
          end
        end

      end

    end

    class Null < Logger
      NAME = "null"
      class <<self
        def open dest = nil
          yield new
        end
      end
      def put **fields
      end
    end

    class Stream < Logger

      class <<self
        def open path = nil, **kwargs
          if path.notempty? and path != "-" then
            params = {}
            %i(external_encoding newline).each do |k|
              v = kwargs.delete k
              params[ k] = v if v
            end
            File.open path, "a", **params do |f|
              yield (new f, **kwargs)
            end
          else
            yield (new $stderr, **kwargs)
          end
        end
      end

      def initialize file, **kwargs
        @file = file
      end

    end

    class Text < Stream
      NAME = "file"
      def initialize file, color: nil, short: nil, maxlen: 256
        super
        @color =
          case color
          when true, false then color
          when 0           then false
          when Integer     then true
          else                  @file.tty?
          end
        @short = short
      end
      COLORS = %w(33 32 34;1 4 31;1 35;1 36)
      def put **fields
        put_sep
        l = [
          ((fields.delete :time).strftime "%H:%M:%S"),
          ((fields.delete :pid).to_s.rjust 5),
          (fields.delete :caller).to_s[ %r([^/]+:\d+)],
          (fields.delete :level),
          (fields.delete :message).inspect,
          (fields.delete :class).plain_name,
          ((fields.map { |k,v| "#{k}:#{v}" }.join " ").axe 256),
        ]
        if @color then
          l = l.zip COLORS
          l.map! do |f,c| "\e[#{c}m#{f}\e[m" end
        end
        if @short then
          s = l.shift 3
          if not @nexttime or @nexttime < Time.now then
            @file.puts s.join " "
            @nexttime = Time.now + 120
          end
        end
        @file.puts l.join " "
        @file.flush
        nil
      end
      def put_sep
        if @file.tty? then
          if not @nextsep or @nextsep < Time.now then
            @file.puts $/*5
            @nextsep = Time.now + 300
          end
        end
      end
    end

    class Plain < Stream
      NAME = "plain"
      def put **fields
        @file.puts fields.to_s
        @file.flush
      end
    end

    class Json < Stream
      NAME = "json"
      def initialize file
        super
        require "json"
        require "time"
      end
      def put **fields
        fields[ :time] = fields[ :time].iso8601 rescue nil
        @file.puts fields.to_json
        @file.flush
      end
    end


    LEVELS = {}
    %i(panic fatal error warn info debug1 debug2 debug3).each_with_index { |l,i| LEVELS[ l] = i }
    LEVELS.default = LEVELS.length
    DEFAULT_LEVEL = :warn

    class <<self

      attr_reader   :level
      attr_accessor :channel

      def level= l
        @level = l.to_sym.downcase
      rescue NoMethodError
        l = l.to_s
        retry
      end

      def put level, message, **kwargs
        return unless @channel
        return if LEVELS[ level] > LEVELS[ @level]
        @channel.put time: Time.now, pid: $$, level: level, message: message, **kwargs
        nil
      rescue
        $stderr.puts "Failed to log: #$! (#{$!.class})"
        $stderr.puts $@
      end

    end


    private

    def log level, message, **kwargs
      Logging.put level, message,
        class: self.class, caller: (caller 1, 1).first,
        **kwargs
    end

    def log_exception level
      Logging.put level, "Exception: #$!",
        class: self.class, caller: (caller 1, 1).first,
        exception: $!.class
      $@.each { |b|
        Logging.put :debug3, "Backtrace", line: b
      }
      nil
    end


    def open_logfile level: nil, path: nil
      level ||= ENV[ "NVIM_RUBY_LOG_LEVEL"].notempty?
      path  ||= ENV[ "NVIM_RUBY_LOG_FILE" ].notempty?
      Logger.provide path do |l|
        ov, Logging.level   = Logging.level,   level||DEFAULT_LEVEL
        ol, Logging.channel = Logging.channel, l
        yield
      ensure
        Logging.level, Logging.channel = ov, ol
      end
    end

  end

end

