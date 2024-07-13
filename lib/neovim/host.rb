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

    attr_reader :plugins

    BASE = :base

    def initialize conn
      super
      DslPlain.open BASE, self do |dsl|
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

    def client_name
      types = @plugins.map { |_,p| p.type if p.type != BASE }
      types.uniq!
      types.compact!
      name = types.join "-"
      log :info, "Client Name", name: name
      "ruby-#{name}-host"
    end

    def client_methods
      r = {}
      @plugins[ BASE].options { |name,opts| r[ name] = opts }
      r
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

