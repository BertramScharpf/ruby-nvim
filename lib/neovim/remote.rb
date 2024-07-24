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

    def initialize conn, plugins = nil
      super
    end

    def start
      @conn.start @comm
      @conn.client
    end

  end

end

