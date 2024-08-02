#
#  lib/neovim/handler.rb  --  Handlers
#

require "neovim/foreign/supplement"


module Neovim

  class Handler

    attr_reader :spec

    def initialize name, type = nil, sync = nil, **options, &block
      @block = block
      standardize options
      @spec = {
        name: name,
        opts: options,
        type: type,
        sync: sync,
      }
      @spec.compact!
    end

    def name ; @spec[ :name] ; end
    def opts ; @spec[ :opts] ; end
    alias options opts
    def sync ; @spec[ :sync] ; end
    alias sync? sync

    def needs_client? ; true ; end
    def execute *args ; @block.call *args ; end

    private

    def standardize opts
      opts.each { |k,v|
        case v
        when false           then opts[ k] = nil
        when true            then opts[ k] = ""
        when String, Integer then
        else                      opts[ k] = v.to_s
        end
      }
      opts.compact!
    end

  end

  class HandlerPlain < Handler

    def initialize *args, **kwargs
      super *args, **kwargs do |client,*a|
        yield *a
      end
    end

    def needs_client? ; false ; end

  end

  class DslBase

    class Plugins

      attr_reader :type

      def initialize type, setups, handlers
        @type, @setups, @handlers = type, setups, handlers
      end

      def setup client
        @setups.each { |b| b.call client }
      end

      def get_handler name
        @handlers[ name]
      end

      def specs
        @handlers.map { |_,handler| handler.spec }
      end

      def options
        @handlers.each { |name,handler| yield name, handler.options }
      end

    end

    include Logging

    class <<self
      private :new
      def open *args
        i = new *args
        yield i
        i.mkplugin
      end
    end

    def initialize
      @setups = []
      @handlers = {}
    end

    def mkplugin
      Plugins.new self.class::TYPE, @setups, @handlers
    end

    private

    HANDLER = Handler

    def add_handler qualified_name, name, type = nil, sync = nil, **opts, &block
      name = name.to_s
      qualified_name ||= name
      h = self.class::HANDLER.new name, type, sync, **opts, &block
      log :info, "Adding Handler", qualified_name: qualified_name, handler: h.spec
      @handlers[ qualified_name] = h
    end

    def add_setup_block &block
      @setups.push block
    end

  end

  class DslPlain < DslBase

    TYPE = nil

    HANDLER = HandlerPlain

    def plain name, **opts, &block
      add_handler nil, name, **opts, &block
    end

  end

  class DslRemote < DslBase

    TYPE = :remote

    def register_handler name, &block
      add_handler nil, name, &block
    end

  end

end

