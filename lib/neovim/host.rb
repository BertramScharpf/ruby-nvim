#
#  neovim/host.rb  --  Host for Neovim
#

require "neovim/remote"
require "neovim/handler"


module Neovim

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
          h.run
          nil
        rescue Remote::Disconnected
          log :fatal, "Disconnected"
          nil
        rescue SignalException
          n = $!.signm.notempty? || $!.class.to_s
          log :fatal, "Signal was caught: #{n}"
          (n =~ /\A(?:SIG)?TERM\z/) ? 0 : 1
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

