#
#  neovim/remote_object.rb  --  Remote Objects: Buffer, Window, Tabpage
#

require "neovim/foreign/mplight"
require "neovim/foreign/mplight/bufferio"


module Neovim

  module OptionAccess

    def get_option name, *args
      vs = [name, *args].map { |a| call_api :get_option_value, a, option_params }
      if args.empty? then
        vs.first
      else
        vs
      end
    end
    alias get_options get_option

    def set_option *args, **kwargs
      op = option_params
      args.each   { |a|   call_api :set_option_value, a, true, op }
      kwargs.each { |k,v| call_api :set_option_value, k, v,    op }
      nil
    end
    alias set_options set_option

    def option_params
      r = {}
      n = self.class::OPTION_PARAM
      r[ n] = @index if n
      r
    end

  end


  class UnknownApiFunction       < RuntimeError ; end
  class UnknownApiObjectFunction < RuntimeError ; end


  class RemoteObject

    class <<self

      alias plain_new new
      def new index, client
        @objs ||= []
        i = @objs.find { |s| s.index == index && s.client == client }
        unless i then
          i = plain_new index, client
          @objs.push i
        end
        i
      end

      def type
        @type ||= plain_name.to_sym
      end

    end

    attr_reader :index, :client

    def initialize index, client
      @index, @client = index, client
    end

    def type
      self.class.type
    end

    def inspect
      "#<#{self.class}:#{self.object_id} #@index>"
    end

    # Neovim packs it twice.
    TRANSFER = MPLight::Types.new
    TRANSFER.extend MPLight::Packer, MPLight::Unpacker
    def to_mpdata packer = nil
      b = MPLight::BufferIO.new
      TRANSFER.do_output b do TRANSFER.put @index end
      b.data
    end
    class <<self
      def from_mpdata data, client
        b = MPLight::BufferIO.new data
        index = TRANSFER.do_input b do TRANSFER.get end
        new index, client
      end
    end

    def == other
      (other.class.equal? self.class) && @index == other.index && @client == other.client
    end


    def call_api name, *args, &block
      @client.call_api name, *args, &block
    end

    def call_obj name, *args, &block
      @client.call_obj self, name, *args, &block
    end


    def method_missing sym, *args
      call_obj sym, *args
    rescue UnknownApiObjectFunction
      super
    end

    def respond_to_missing? sym, priv = nil
      @client.has_obj_function? self, sym
    end

    def methods regular = true
      s = super
      s |= @client.obj_functions self if regular
      s
    end

    include OptionAccess

  end



  class Buffer < RemoteObject

    # Functions as described in ":h ruby"

    def name   ; call_obj :get_name   ; end
    def number ; index                ; end

    def count  ; call_obj :line_count ; end
    alias length count

    def [] pos = nil, len = nil
      line_indices pos, len do |fst,lst|
        get_lines fst, lst, false
      end
    end

    def []= pos = nil, len = nil, str
      line_indices pos, len do |fst,lst|
        set_lines fst, lst, false, (Neovim.result_lines str)
      end
      self
    end

    def delete pos, len = nil ; self[pos, len] = nil ; end

    def insert pos = nil, str
      self[ pos||0, 0] = str
    end

    def append pos = nil, str
      p = (pos||0) + 1
      insert p, str
    end


    # Legacy functions

    def line
      call_api :get_current_line if active?
    end

    def line= str
      raise "Buffer not active. Use Buffer#[]= instead." unless active?
      call_api :set_current_line, str
    end

    def line_number
      (call_api :get_current_win).line if active?
    end


    def active?
      (call_api :get_current_buf).index == @index
    end


    OPTION_PARAM = :buf


    # Iterating functions

    include Enumerable

    def each pos = nil, len = nil, &block
      if block_given? then
        iter_chunks pos, len do |l|
          l.each &block
        end
      else
        Enumerator.new { |y| each { |x,i| y.yield x, i } }
      end
    end

    def map! pos = nil, len = nil, &block
      if block_given? then
        iter_chunks pos, len do |l|
          n = l.length
          h = l.hash
          m = l.map &block
          if m.hash != h or m != l then
            r = Neovim.result_lines m
            set_lines @fst, @fst+n, true, r
            inc = r.length - n
            @fst += inc
            @lst += inc
          end
        end
      else
        Enumerator.new { |y| map! { |x,i| y.yield x, i } }
      end
    end
    alias collect! map!

    def reject! pos = nil, len = nil, &block
      if block_given? then
        iter_chunks pos, len do |l|
          n = l.length
          l.reject! &block
          if l.length < n then
            set_lines @fst, @fst+n, true, l
            inc = l.length - n
            @fst += inc
            @lst += inc
          end
        end
      else
        Enumerator.new { |y| map! { |x,i| y.yield x, i } }
      end
    end
    alias delete_if reject!

    def select!
      if block_given? then
        reject! { |l| not (yield l) }
      else
        Enumerator.new { |y| select! { |l| y.yield l } }
      end
    end
    alias filter! select!

    # Don't run into `method_missing`.
    def get_lines fst, lst, strict      ; call_obj :get_lines, fst, lst, strict      ; end
    def set_lines fst, lst, strict, ary ; call_obj :set_lines, fst, lst, strict, ary ; end


    private

    def line_indices pos, len
      if Range === pos then
        r = pos
        pos, lst = r.begin||1, r.end||-1
        lst += 1 unless r.exclude_end?
      elsif pos.nil? then
        pos, lst = 1, 0
      else
        lst = pos+1
      end
      if len then
        lst = pos + (len >= 0 ? len : 0)
      end
      lst = 0 if pos < 0 and lst > 0
      yield pos-1, lst-1
    end

    def line_indices_positive pos, len
      line_indices pos, len do |*fl|
        c = nil
        fl.map! { |y|
          unless y >= 0 then
            c ||= count
            y += 1 + c
          end
          y
        }
        yield *fl
      end
    end

    @chunk_length = 1024
    class <<self
      attr_accessor :chunk_length
    end

    def iter_chunks pos, len
      line_indices_positive pos, len do |fst,lst|
        @fst, @lst = fst, lst
        while @fst < @lst do
          l = get_lines @fst, @fst+self.class.chunk_length, false
          yield l
          @fst += self.class.chunk_length
        end
      end
    ensure
      @fst = @lst = nil
    end

  end


  class Window < RemoteObject

    def number ; call_obj :get_number ; end

    def buffer ; call_obj :get_buf ; end

    def height    ; call_obj :get_height    ; end
    def height= n ; call_obj :set_height, n ; end

    def width    ; call_obj :get_width    ; end
    def width= n ; call_obj :set_width, n ; end

    def line       ; cursor.first ; end

    def cursor     ; call_obj :get_cursor     ; end
    def cursor= yx ; call_obj :set_cursor, yx ; end

    def save_cursor
      c = cursor
      yield
      self.cursor = c
    end

    OPTION_PARAM = :win

  end


  class Tabpage < RemoteObject

    def number ; call_obj :get_number ; end

    # There is currently only one tabpage-local option, 'cmdheight'.
    OPTION_PARAM = :tab     # Neovim is missing this.

  end


  class <<self

    def result_lines obj
      case obj
      when Enumerable then obj.inject [] do |s,l| s.push *(result_lines l) end
      when nil        then []
      else                 obj.to_s.scan /^.*$/
      end
    end

  end

end

