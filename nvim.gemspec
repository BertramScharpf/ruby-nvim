#
#  nvim.gemspec  --  Gem specification
#

system *%w(rake infofile)

$:.unshift "./lib"
require "neovim/info"


Gem::Specification.new do |spec|
  Neovim::INFO.mk_gemspec spec
  spec.required_ruby_version = Gem::Requirement.new ">= 3.1.0"

  spec.files         = Dir[ "lib/**/*.rb"] + Dir[ "bin/*"]

  spec.require_paths = %w(lib)
  spec.bindir        = "bin"
  spec.executables   = %w(neovim-ruby-host)

  spec.extra_rdoc_files =  %w(INFO.yaml LICENSE README.md)
  spec.extra_rdoc_files += %w(Rakefile nvim.gemspec)
  spec.extra_rdoc_files += Dir[ "examples/*"]

  if false then
    spec.add_dependency "supplement", "~> 2.18"
    spec.add_dependency "mplight",    "~> 1.0"
  end

end

