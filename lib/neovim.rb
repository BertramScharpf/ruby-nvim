#
#  neovim.rb  --  Basic methods
#

require "neovim/host"


module Neovim

  class <<self

    def start_remote &block
      Host.run do |h|
        p = DslRemote.open &block
        h.add_plugins :remote, p
        h.start
      end
    end

  end

end

