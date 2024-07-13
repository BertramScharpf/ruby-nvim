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

    class UnknownApiFunction       < RuntimeError ; end
    class UnknownApiObjectFunction < RuntimeError ; end


    attr_reader :channel_id

    def initialize comm, channel_id
      @comm, @channel_id = comm, channel_id
      @functions = {}
      @objfuncs  = Hash.new do |h,k| h[k] = {} end
    end

    def inspect
      "#<#{self.class} #@channel_id>"
    end

    def add_functions list, prefixes
      list.each { |fn|
        next if fn[ "deprecated_since"] && self.class.strict
        n = fn[ "name"]
        next unless n =~ /\Anvim_/
        @functions[ $'.to_sym] = n
        t, = prefixes.find { |t,p| n =~ p }
        @objfuncs[ t][ $'.to_sym] = n if t
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


    def has_obj_function? obj, name
      @objfuncs[ obj.type][ name.to_sym].to_bool
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

    def evaluate expr ; call_api :eval, expr ; end

  end

end

