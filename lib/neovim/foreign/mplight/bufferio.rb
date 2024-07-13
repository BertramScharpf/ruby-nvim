#
#  neovim/foreign/mplight/bufferio.rb  --  Buffer behaving like an IO
#

# The purpose of this is simply to reduce dependencies.

begin
  require "mplight/bufferio"
rescue LoadError

# ----------------------------------------------------------------
#
#  mplight/bufferio.rb  --  Buffer behaving like an IO
#


module MPLight

  class BufferIO

    attr_reader :data

    def initialize str = nil
      @data = str||""
    end

    def binmode
      @data.force_encoding Encoding::ASCII_8BIT
    end
    def sync= _ ; end
    def sync    ; true ; end

    def write d
      @data << d
    end

    def read n
      @data.slice! 0, n
    end

    def flush
    end

  end

end

# ----------------------------------------------------------------

end

