#
#  neovim/client.rb  --  Clients
#

require "neovim/foreign/supplement"

require "neovim/remote_object"


module Neovim

  class Client

    @strict = true
    class <<self
      attr_accessor :strict
    end


    attr_reader :channel_id

    def initialize comm, channel_id
      @comm, @channel_id = comm, channel_id
      @functions = {}
      @objfuncs  = {}
    end

    def inspect
      "#<#{self.class} #@channel_id>"
    end

    def add_functions list, prefixes
      list.each { |fn|
        next if fn[ "deprecated_since"] && self.class.strict
        n = fn[ "name"]
        if (b = n.starts_with? "nvim_") then
          @functions[ n[ b...].to_sym] = n
        end
        prefixes.each { |t,p|
          if (b = n.starts_with? p) then
            @objfuncs[ t] ||= {}
            @objfuncs[ t][ n[ b...].to_sym] = n
            break
          end
        }
      }
    end


    def call_api name, *args
      f = @functions[ name.to_sym]
      f or raise UnknownApiFunction, "Function: #{name}"
      @comm.request f, *args
    end

    def call_obj obj, name, *args
      n = obj.type
      f = @objfuncs[ n.to_sym][ name.to_sym]
      f or raise UnknownApiObjectFunction, "Object: #{n}, Function: #{name}"
      @comm.request f, obj.index, *args
    end


    def method_missing sym, *args
      call_api sym, *args
    rescue UnknownApiFunction
      super
    end

    def respond_to_missing? sym, priv = nil
      # Be aware that calling a proc (our handlers) with a single argument
      # asks whether that argument is an array. In case it is a Client object,
      # we end up here with +sym = to_ary+.
      @functions[ sym.to_sym].to_bool
    end

    def methods regular = true
      s = super
      s |= @functions.keys if regular
      s
    end

    def functions
      @functions.keys
    end


    def has_obj_function? obj, name
      @objfuncs[ obj.type][ name.to_sym].to_bool
    end

    def obj_classes
      RemoteObject.subclasses.select { |c| @objfuncs[ c.type] rescue nil }
    end

    def obj_functions obj
      @objfuncs[ obj.type].keys
    end


    def message str
      call_api :out_write, str
      str.end_with? $/ or call_api :out_write, $/
    end


    include OptionAccess
    OPTION_PARAM = nil

    def command arg ; call_api :command, arg ; end

    # Be aware that #eval was a private instance method from module Kernel.
    def evaluate expr ; call_api :eval, expr ; end

  end

  class Lines

    include Enumerable

    def initialize client, range
      case client
      when Buffer then @client, @buffer = client.client, client.index
      else             @client, @buffer = client,        0
      end
      @i, @last = range.begin, range.end
    end

    def to_s
      (@client.buf_get_lines @buffer, @i-1, @last, true).join $/
    end

    def method_missing sym, *args, **kwargs, &block
      to_a.send sym, *args, **kwargs, &block
    end

    def each
      while @i <= @last do
        @inc = 1
        l, = @client.buf_get_lines @buffer, @i-1, @i, true
        yield l
        @i += @inc
      end
    ensure
      @i = nil
    end
    alias each_line each

    def each_with_no
      each do |l|
        yield l, @i
      end
    end

    def map!
      each do |l|
        h = l.hash
        m = yield l, @i
        r =
          case m
          when String     then m.lines unless m.hash == h
          when Enumerable then m.map { |l| l.to_s }
          when nil, false then []
          end
        if r then
          r.each { |l| l.chomp! }
          @client.buf_set_lines @buffer, @i-1, @i, true, r
          @inc = r.length
          @last += @inc-1
        end
      end
    end

  end

end

