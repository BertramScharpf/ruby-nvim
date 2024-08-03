#
#  neovim.rb  --  Basic methods
#

require "neovim/host"


module Neovim

  class Job < Provider

    def initialize plugins, conn
      super plugins, conn
      start
    end

  end

  class <<self

    def start_remote &block
      Job.run mk_plugins &block
    end

    def mk_plugins &block
      { remote: (DslRemote.open &block) }
    end

  end

end

