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

    def execute *args
      @block.call *args
    end

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

  class DslBase

    class Plugins

      attr_reader :type

      def initialize type, setup_blocks, handlers
        @type, @setup_blocks, @handlers = type, setup_blocks, handlers
      end

      def setup client
        @setup_blocks.each { |b| b.call client }
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
      def open source, host
        i = new source
        yield i
        i.add_plugins source, host
      end
    end

    def initialize source
      @setup_blocks = []
      @handlers = {}
    end

    def add_plugins source, host
      host.add_plugins source, (Plugins.new self.class::TYPE, @setup_blocks, @handlers)
    end

    private

    def add_handler qualified_name, name, type = nil, sync = nil, **opts, &block
      name = name.to_s
      qualified_name ||= name
      h = Handler.new name, type, sync, **opts, &block
      log :info, "Adding Handler", qualified_name: qualified_name, handler: h.spec
      @handlers[ qualified_name] = h
    end

    def add_setup_block &block
      @setup_blocks.push block
    end

  end

  class DslPlain < DslBase

    TYPE = :base

    def plain name, **opts
      add_handler nil, name, **opts do |client,*args|
        yield *args
      end
    end

  end

  class DslRemote < DslBase

    TYPE = :remote

    def register_handler name, &block
      add_handler nil, name, &block
    end

  end

end

