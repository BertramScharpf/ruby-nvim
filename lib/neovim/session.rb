#
#  neovim/session.rb  --  Sessions
#

require "neovim/foreign/supplement"

require "neovim/logging"
require "neovim/connection"
require "neovim/messager"


module Neovim

  class Session

    include Logging

    class <<self

      private :new

      def open conntype, *args, **kwargs
        conntype.open_files *args, **kwargs do |conn|
          yield (new conn)
        end
      end

      include Logging

      def start *args
        open_logfile do
          log :info, "Starting", args: $*
          open *args do |i|
            yield i
          end
        ensure
          log :info, "Leaving"
        end
      end

    end

    def initialize conn
      @conn = conn
      @comm = Messager.new @conn, self
    end

    def execute_handler name, args
      raise "No handler found for #{name.inspect}."
    end


    def run ; @comm.run ; end
    def request method, *args ; @comm.request method, *args ; end
    def notify  method, *args ; @comm.notify  method, *args ; end

  end

end

