#
#  neovim/foreign/mplight.rb  --  Lightweight MessagePack implementation
#

# The purpose of this is simply to reduce dependencies.

begin
  require "mplight"
rescue LoadError

# ----------------------------------------------------------------
#
#  mplight.rb  --  Lightweight MessagePack implementation
#


module MPLight

  VERSION = "1.0".freeze

  class Error ; end


  class Types

    def initialize *args, **kwargs
      @cls = {}
      @ids = {}
      register -1, Time
    end

    def register id, klass
      @cls[ id], @ids[ klass] = klass, id
    end

    def dump obj
      t = @ids[ obj.class]
      unless t then
        return if @default_to_string
        raise Error, "Unregistered class: #{obj.class}"
      end
      [ t, obj.to_mpdata]
    end

    def default_to_string! ; @default_to_string = true ; end

    def create id, data
      c = @cls[ id]
      c or raise Error, "Unregistered type id: #{obj.class}"
      c.from_mpdata data, *additional_data
    end

    def additional_data
      []
    end

  end


  module Packer

    attr_reader :output

    def init_output output
      @output = output
      @output.binmode
      @output.sync = true
      self
    end

    def do_output output
      oi = @output
      init_output output
      yield
    ensure
      @output = oi
    end

    def put obj
      case obj
      when nil   then write_fmt 0xc0
      when false then write_fmt 0xc2
      when true  then write_fmt 0xc3
      when Integer then
        if obj >= 0 then
          case obj
          when                ...0x80 then write_fmt obj
          when               ...0x100 then write_fmt 0xcc ; write_pack obj, "C"
          when             ...0x10000 then write_fmt 0xcd ; write_pack obj, "S>"
          when         ...0x100000000 then write_fmt 0xce ; write_pack obj, "L>"
          when ...0x10000000000000000 then write_fmt 0xcf ; write_pack obj, "Q>"
          else                                 raise ArgumentError, "Integer too large: #{obj}"
          end
        else
          case obj
          when               -0x20... then write_fmt obj+256
          when               -0x80... then write_fmt 0xd0 ; write_pack obj, "c"
          when             -0x8000... then write_fmt 0xd1 ; write_pack obj, "s>"
          when         -0x80000000... then write_fmt 0xd2 ; write_pack obj, "l>"
          when -0x8000000000000000... then write_fmt 0xd3 ; write_pack obj, "q>"
          else                             raise ArgumentError, "Integer too large: #{obj}"
          end
        end
      when Float then
        case
        when false then write_fmt 0xca ; write_pack obj, "g"
        else            write_fmt 0xcb ; write_pack obj, "G"
        end
      when String then
        if obj.encoding == Encoding::ASCII_8BIT then
          l = obj.size
          case l
          when       ...0x100 then write_fmt 0xc4 ; write_pack l, "C"
          when     ...0x10000 then write_fmt 0xc5 ; write_pack l, "S>"
          when ...0x100000000 then write_fmt 0xc6 ; write_pack l, "L>"
          else                     raise ArgumentError, "Byte array too long: #{l} bytes"
          end
        else
          obj = obj.encode Encoding::UTF_8 unless obj.encoding == Encoding::UTF_8
          l = obj.bytesize
          case l
          when        ...0x20 then write_fmt 0xa0+l
          when       ...0x100 then write_fmt 0xd9 ; write_pack l, "C"
          when     ...0x10000 then write_fmt 0xda ; write_pack l, "S>"
          when ...0x100000000 then write_fmt 0xdb ; write_pack l, "L>"
          else                     raise ArgumentError, "String too long: #{l} bytes"
          end
        end
        write_pack obj, "A*"
      when Array then
        l = obj.length
        case l
        when        ...0x10 then write_fmt 0x90+l
        when     ...0x10000 then write_fmt 0xdc ; write_pack l, "S>"
        when ...0x100000000 then write_fmt 0xdd ; write_pack l, "L>"
        else                     raise ArgumentError, "Array too long: #{l} elements"
        end
        obj.each { |o| put o }
      when Hash then
        l = obj.length
        case l
        when        ...0x10 then write_fmt 0x80+l
        when     ...0x10000 then write_fmt 0xde ; write_pack l, "S>"
        when ...0x100000000 then write_fmt 0xdf ; write_pack l, "L>"
        else                     raise ArgumentError, "Hash too long: #{l} keys"
        end
        obj.each { |k,v| put k ; put v }
      when Symbol then
        put obj.to_s
      else
        type, data = dump obj
        type or return put obj.to_s
        l = data.bytesize
        case l
        when           0x01 then write_fmt 0xd4 ;                      write_pack type, "c"
        when           0x02 then write_fmt 0xd5 ;                      write_pack type, "c"
        when           0x04 then write_fmt 0xd6 ;                      write_pack type, "c"
        when           0x08 then write_fmt 0xd7 ;                      write_pack type, "c"
        when           0x10 then write_fmt 0xd8 ;                      write_pack type, "c"
        when       ...0x100 then write_fmt 0xc7 ; write_pack l, "C"  ; write_pack type, "c"
        when     ...0x10000 then write_fmt 0xc8 ; write_pack l, "S>" ; write_pack type, "c"
        when ...0x100000000 then write_fmt 0xc9 ; write_pack l, "L>" ; write_pack type, "c"
        else                     raise ArgumentError, "Object too large: #{l} bytes"
        end
        write_pack data, "A*"
      end
      self
    end

    private

    def write_pack i, t
      d = [i].pack t
      @output.write d
    end

    def write_fmt i
      write_pack i, "C"
    end

  end


  module Unpacker

    attr_reader :input

    def init_input input
      @input = input
      @input.binmode
      self
    end

    def do_input input
      oi = @input
      init_input input
      yield
    ensure
      @input = oi
    end

    def eof?
      @input.eof?
    end

    def get
      fmt = (read 1).unpack1 "C"
      case fmt >> 7
      when 0b0 then fmt
      else
        case fmt >> 5
        when 0b111 then fmt - 256
        when 0b101 then get_str fmt&0b11111
        else
          case fmt >> 4
          when 0b1000 then get_hsh fmt&0b1111
          when 0b1001 then get_ary fmt&0b1111
          else
            case fmt
            when 0xc0 then nil
            when 0xc1 then raise ArgumentError, "Illegal format: #{fmt}"
            when 0xc2 then false
            when 0xc3 then true
            when 0xc4 then read    get_len1
            when 0xc5 then read    get_len2
            when 0xc6 then read    get_len4
            when 0xc7 then get_ext get_len1
            when 0xc8 then get_ext get_len2
            when 0xc9 then get_ext get_len4
            when 0xca then (read 4).unpack1 "g"
            when 0xcb then (read 8).unpack1 "G"
            when 0xcc then (read 1).unpack1 "C"
            when 0xcd then (read 2).unpack1 "S>"
            when 0xce then (read 4).unpack1 "L>"
            when 0xcf then (read 8).unpack1 "Q>"
            when 0xd0 then (read 1).unpack1 "c"
            when 0xd1 then (read 2).unpack1 "s>"
            when 0xd2 then (read 4).unpack1 "l>"
            when 0xd3 then (read 8).unpack1 "q>"
            when 0xd4 then get_ext  1
            when 0xd5 then get_ext  2
            when 0xd6 then get_ext  4
            when 0xd7 then get_ext  8
            when 0xd8 then get_ext 16
            when 0xd9 then get_str get_len1
            when 0xda then get_str get_len2
            when 0xdb then get_str get_len4
            when 0xdc then get_ary get_len2
            when 0xdd then get_ary get_len4
            when 0xde then get_hsh get_len2
            when 0xdf then get_hsh get_len4
            end
          end
        end
      end
    end

    private

    def read n
      @input.read n
    end

    def get_len1 ; (read 1).unpack1 "C"  ; end
    def get_len2 ; (read 2).unpack1 "S>" ; end
    def get_len4 ; (read 4).unpack1 "L>" ; end

    def get_str len
      (read len).force_encoding Encoding::UTF_8
    end

    def get_ary len
      (0...len).map { get }
    end

    def get_hsh len
      (0...len).inject Hash.new do |h,| k = get ; h[k] = get ; h end
    end

    def get_ext len
      type = (read 1).unpack1 "c"
      create type, (read len)
    end

  end

end


class Time

  class <<self

    def from_mpdata data, *args
      case data.length
      when  4 then
        s, = data.unpack "L>"
        Time.at s
      when  8 then
        t, = data.unpack "Q>"
        n = t >> 34
        t &= 0x3ffffffff
        Time.at t, n, :nanosecond
      when 12 then
        n, s = data.unpack "L>Q>"
        Time.at s, n, :nanosecond
      else
        raise ArgumentError, "Illegal time data: #{data.inspect}"
      end
    end

  end

  def to_mpdata
    case
    when tv_nsec.zero? && tv_sec < 0x100000000 then [ tv_sec].pack "L>"
    when                  tv_sec < 0x400000000 then [ (tv_nsec << 34)|tv_sec].pack "Q>"
    else                                            [ tv_nsec, tv_sec].pack "L>Q>"
    end
  end

end

# ----------------------------------------------------------------

end

