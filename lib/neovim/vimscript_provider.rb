#
#  neovim/vimscript_provider.rb  --  Remote Plugin
#

require "neovim/handler"


module Neovim

  class DslVimscript < DslBase

    TYPE = :rplugin

    def initialize source
      super *[]
      @source = source
    end

    def command name, sync: true, **options, &block
      # Options: range/count bang register nargs complete bar
      register_handler :command, name, sync, **options, &block
    end

    def function name, sync: true, **options, &block
      # Options: range eval
      register_handler :function, name, sync, **options, &block
    end

    def autocmd event, **options, &block
      # Options: group pattern nested once eval
      register_handler :autocmd, event, true, **options, &block
    end

    private

    def register_handler type, name, sync, **opts
      acp = opts[ :pattern]||"*" if type == :autocmd
      qn = [ @source, type, name, *acp].join ":"
      add_handler qn, name, type, sync, **opts do |client,*args|
        args, range, evaled = *args
        range = Range.new *range if range
        yield client, args, range, evaled
      end
    end

  end

end

