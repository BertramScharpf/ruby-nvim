#
#  neovim/remote.rb  --  Host for Neovim
#

require "neovim/session"
require "neovim/handler"


module Neovim

  class Remote < Session

    class <<self

      def start_client *args
        start *args do |i|
          yield i.start
        end
      end

    end

    def initialize conn
      super
      @plugins = {}
    end

    def start
      @conn.start @comm, client_name, self.class.plain_name, client_methods
      @conn.client
    end

    def client_name    ; "ruby-client" ; end
    def client_methods ;                 end


    def add_plugins source, plugins
      @plugins[ source] = plugins
    end

    def execute_handler name, args
      @plugins.each_value do |plugin|
        handler = plugin.get_handler name
        if handler then
          log :info, "Found handler", name: name
          log :debug1, "Calling with", args: args
          return handler.execute @conn.client, *args
        end
      end
      super
    end

  end

end

