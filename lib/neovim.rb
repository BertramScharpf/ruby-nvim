#
#  neovim.rb  --  Basic methods
#

require "neovim/host"


module Neovim

  class <<self

    def start_remote &block
      Host.run do |h|
        DslRemote.open :remote, h, &block
        h.start
      end
    end

  end

end

