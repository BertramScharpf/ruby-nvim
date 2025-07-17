#
#  neovim/foreign/supplement/socket.rb  --  Addition usefull Ruby socket functions
#

# The purpose of this is simply to reduce dependencies.

begin
  require "supplement/socket"
rescue LoadError
  require "socket"
  class BasicSocket
    private def with_close socket
      if block_given? then
        begin
          yield socket
        ensure
          socket.close
        end
      else
        socket
      end
    end
  end
  class TCPServer
    alias accept_orig accept
    private :accept_orig
    def accept &block ; with_close accept_orig, &block ; end
  end
  class UNIXServer
    alias accept_orig accept
    private :accept_orig
    def accept &block ; with_close accept_orig, &block ; end
  end
end

