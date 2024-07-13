#
#  neovim/foreign/supplement/socket.rb  --  Addition usefull Ruby socket functions
#

# The purpose of this is simply to reduce dependencies.

begin
  require "supplement/socket"
rescue LoadError
  require "socket"
  class TCPServer
    alias accept_orig accept
    private :accept_orig
    def accept
      a = accept_orig
      if block_given? then yield a else a end
    end
  end
end

