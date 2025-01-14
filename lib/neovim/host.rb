#
#  neovim/host.rb  --  Host for Neovim
#

require "neovim/remote"
require "neovim/handler"


module Neovim

  class Remote

    class <<self

      def run_remote *args, **kwargs, &block
        plugins = { remote: (DslRemote.open &block), }
        start plugins, *args, **kwargs do |i|
          i.start
          i.run
        end
      rescue Remote::Disconnected
      end

      def run_sub socket: nil, timeout: nil, &block
        socket ||= "/tmp/nvim-sub-#$$.sock"
        f = fork { exec *%w(nvim --listen), socket }
        Remote.run_remote ConnectionUnix, socket, timeout: timeout||1, &block
      ensure
        Process.waitpid f
      end

    end

  end


  class Provider < Remote

    class <<self

      def start plugins
        super plugins, ConnectionStdio do |h|
          yield h
        end
      end

      def run plugins
        $stdin.tty? and raise "This program expects to be called by Neovim. It can't run interactively."
        start plugins do |h|
          log :info, "Starting event loop."
          h.run
          nil
        rescue Remote::Disconnected
          log :fatal, "Disconnected"
          nil
        rescue SignalException
          n = $!.signm.notempty? || $!.class.to_s
          if n =~ /\A(?:SIG)?TERM\z/ then
            log :info, "Exiting after terminate signal."
            nil
          else
            log :fatal, "Signal was caught: #{n}"
            1
          end
        rescue Exception
          log_exception :fatal
          2
        end
      end

    end

  end

  class Host < Provider

    def initialize plugins, conn
      super plugins, conn
      @plugins[ :base] = DslPlain.open do |dsl|
        dsl.plain "poll" do
          start
          "ok"
        end
        dsl.plain "specs", nargs: 1 do |source|
          p = @plugins[ source]
          p or raise "Unknown plugin #{source}"
          p.specs
        end
        dsl.plain "nvim_error_event", nargs: 2 do |errid,msg|
          raise "#{@conn.error errid} from Neovim: #{msg}"
        end
      end
    end

  end

end

