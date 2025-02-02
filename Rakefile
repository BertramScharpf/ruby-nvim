#
#  Rakefile  --  Generate files
#


INFOFILE = "lib/neovim/info.rb"


GENERATED = [ INFOFILE]

task :default => GENERATED
task :infofile => INFOFILE


file INFOFILE => "INFO.yaml" do |f|
  create_info f.name, f.source
end


task :clean do
  rm *GENERATED
end


def commit
  c = `git rev-parse --short HEAD`
  c.chomp!
  c
end

def create_info dst, src
  File.open dst, "w" do |vf|
    require "yaml"
    m = YAML.load File.read src
    name = m.keys.first
    args = m[ name]
    args[ :commit] = commit
    unless args[ :authors] then
      u = args.delete :author
      args[ :authors] = [ u] if u
    end
    vf.puts 'require "neovim/meta.rb"'
    vf.print "Neovim::INFO = Neovim::Meta.new #{name.inspect}"
    args.each { |k,v|
      vf.puts ","
      vf.print "  #{k.to_sym}: #{v.inspect}"
    }
    vf.puts
  end
end


task :diffdeps do
  %w(mplight nxxd).each { |gem|
    c = `gem contents #{gem}`
    unless $?.success? then
      puts "Gem #{gem} not installed. Cannot compare."
      next
    end
    (c.split $/).each { |file|
      if file =~ %r[/gems/#{gem}-.*/lib/(.*\.rb)$] then
        ours = "lib/neovim/foreign/#$1"
        sh *%W(nvim -d #{ours} #{file}) if File.exist? ours
      end
    }
  }
end

