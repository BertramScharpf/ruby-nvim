#
#  neovim/foreign/xxd.rb  --  Xxd reimplementation
#

# The purpose of this is simply to reduce dependencies.

begin
  require "xxd"
rescue LoadError

# ----------------------------------------------------------------
#
#  xxd.rb  --  A Reimplementation of Xxd in plain Ruby
#

module Xxd

  module ReadChunks

    private

    def read_chunks input
      case input
      when String then
        i = 0
        while i < input.bytesize do
          b = input.byteslice i, @line_size
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
    end

    class <<self

      def reverse input
        r = nil
        pos = 0
        repeat = false
        input.each_line { |l|
          case l
            when /^\s*#/ then
            when /^\*/   then repeat = true
            else
              if (l.slice! /^(\h+):\s*/) then
                addr = $1.to_i 0x10
                if repeat then
                  while pos + r.length < addr do
                    yield r
                    pos += r.length
                  end
                  if pos < addr then
                    yield r[ 0, addr - pos]
                    pos = addr
                  end
                  repeat = false
                else
                  if pos < addr then
                    r = ([0].pack "C*") * (addr - pos)
                    yield r
                    pos = addr
                  elsif pos > addr then
                    yield nil, addr
                    pos = addr
                  end
                end
              end
              row = []
              while (nib = l.slice! /^\h\h ?/) do
                row.push nib.to_i 0x10
              end
              if row.any? then
                r = row.pack "C*"
                yield r
                pos += r.length
              end
          end
        }
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
        yield "};"
        len = run_plain input, &block
        yield "unsigned int #@varname\_len = %d;" % len
      else
        run_plain input, &block
      end
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

end

# ----------------------------------------------------------------

end

