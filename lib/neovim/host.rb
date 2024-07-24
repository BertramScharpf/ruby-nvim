#
#  neovim/host.rb  --  Host for Neovim
#

require "neovim/remote"


module Neovim

  class Host < Remote

    class <<self

      def start
        super ConnectionStdio do |h|
          yield h
        end
      end

    end

    def initialize conn
      @plugins = {}
      super conn, @plugins
      DslPlain.open :base, self do |dsl|
        dsl.plain "poll" do
          start
          @plugins.each_value { |p| p.setup @conn.client }
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

    def add_plugins source, plugins
      @plugins[ source] = plugins
    end

    class <<self

      def run
        $stdin.tty? and raise "This program expects to be called by Neovim. It can't run interactively."
        Host.start do |h|
          yield h
          h.run
          nil
        rescue Messager::Disconnected
          log :fatal, "Disconnected"
          nil
        rescue SignalException
          n = $!.signm
          log :fatal, "Signal was caught: #{n}"
          (n =~ /\A(?:SIG)?TERM\z/) ? 0 : 1
        rescue Exception
          log_exception :fatal
          2
        end
      end

    end

  end

end

