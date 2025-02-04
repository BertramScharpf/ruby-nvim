#
#  neovim/foreign/nxxd.rb  --  Hex Dump Tool
#

# The purpose of this is simply to reduce dependencies.

begin
  require "nxxd"
rescue LoadError

# ----------------------------------------------------------------
#
#  nxxd.rb  --  Hex Dump Tool
#


module Nxxd

  module ReadChunks

    private

    def read_chunks input
      case input
      when String then
        i = 0
        while i < input.bytesize do
          b = input.byteslice i, @line_size
          b.force_encoding Encoding::ASCII_8BIT  # Ruby, shouldn't this rather be self-evident?
          yield b
          i += @line_size
        end
      else
        loop do
          b = input.read @line_size
          break unless b
          yield b
          break if b.length < @line_size
        end
      end
    end

  end

  class Dump

    include ReadChunks

    LINE_SIZE = 16
    ADDR_FMT = "%%0%dx:"

    def initialize full: nil, upper: false, line_size: nil, addr_len: nil, input: nil
      @full = full
      @input = input
      @line_size = line_size||LINE_SIZE
      @addr_fmt = ADDR_FMT % (addr_len||8)
      @nib_fmt = "%02x"
      if upper then
        @addr_fmt.upcase!
        @nib_fmt.upcase!
      end
    end

    def run input
      addr = 0
      prev, repeat = nil, false
      yield "# #@input" if @input
      read_chunks input do |b|
        if b == prev and not @full then
          unless repeat then
            yield "*"
            repeat = true
          end
        else
          r = @addr_fmt % addr
          r << " "
          h =  b.unpack "C*"
          sp = false
          @line_size.times {
            x = h.shift
            r << (x ? @nib_fmt % x : "  ")
            r << " " if sp
            sp = !sp
          }
          r << " " << (b.gsub /[^ -~]/, ".")
          yield r
          prev, repeat = b, false
        end
        addr += b.size
      end
      yield @addr_fmt % addr
      nil
    end


    class <<self

      def reverse input, output = nil
        output ||= ""
        o = String === output ? (WriteChunksString.new output) : output
        o.set_encoding Encoding::ASCII_8BIT
        r, repeat = nil, false
        input.each_line { |l|
          l.chomp!
          case l
            when /^\s*(?:#|$)/                  then nil
            when /^\*/                          then repeat = true
            when /^(?:(\h+):)?\s*((?:\h\h ?)*)/ then
              addr, nibs = $~.captures
              if addr then
                addr = $1.to_i 0x10
                if repeat then
                  loop do
                    s = addr - o.tell
                    break if s <= 0
                    o.write s >= r.length ? r : r[ 0, s]
                  end
                  repeat = false
                else
                end
                o.seek addr
              end
              r = (nibs.scan /\h\h/).map { |x| x.to_i 0x10 }.pack "C*"
              o.write r
            else
              raise "Uninterpretable hex dump: #{l.chomp}"
          end
        }
        output
      end

    end

  end

  class DumpNums

    include ReadChunks

    LINE_SIZE = 12

    def initialize upper: false, line_size: nil, capitals: nil, input: nil
      @line_size = line_size||LINE_SIZE
      @nib_fmt = "%#04x"
      @nib_fmt.upcase! if upper
      if input then
        @varname = input.dup
        @varname.insert 0, "__" if @varname =~ /\A\d/
        @varname.gsub! /[^a-zA-Z0-9]/, "_"
        @varname.upcase! if capitals
      end
    end

    def run input, &block
      if @varname then
        yield "unsigned char #@varname[] = {"
        len = run_plain input, &block
        yield "};"
        yield "unsigned int #@varname\_len = %d;" % len
      else
        run_plain input, &block
      end
      nil
    end

    private

    def run_plain input
      prev, len = nil, 0
      read_chunks input do |b|
        if prev then
          prev << ","
          yield prev
        end
        prev = "  " + ((b.unpack "C*").map { |x| @nib_fmt % x }.join ", ")
        len += b.bytesize
      end
      yield prev if prev
      len
    end

  end

  class WriteChunksString
    def initialize str
      @str = str
    end
    def set_encoding enc
      @str.force_encoding enc
    end
    def tell ; @pos || @str.length ; end
    def seek pos
      s = pos - @str.length
      if s >= 0 then
        s.times { @str << "\0".b }
      else
        @pos = pos
      end
    end
    def write b
      if @pos then
        l = b.length
        @str[ @pos, l] = b
        @pos += l
        @pos = nil if @pos >= @str.length
      else
        @str << b
      end
    end
  end

end

# ----------------------------------------------------------------

end

