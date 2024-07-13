#
#  nvim.gemspec  --  Gem specification
#

system *%w(rake infofile)

$:.unshift "./lib"
require "neovim/info"


Gem::Specification.new do |spec|
  Neovim::INFO.mk_gemspec spec

  spec.files         = Dir["[A-Z]*"] + Dir[ "lib/**/*.rb"] + Dir[ "bin/*"]

  spec.require_paths = ["lib"]
  spec.bindir        = "bin"
  spec.executables   = ["neovim-ruby-host"]

  spec.required_ruby_version = Gem::Requirement.new ">= 3.0.0"

  if false then
    spec.add_dependency "supplement", "~> 2.18"
    spec.add_dependency "mplight",    "~> 1.0"
  end
end

