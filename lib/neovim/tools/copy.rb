#
#  neovim/tools/copy.rb  --  Set X11 selection and Tmux buffer
#


module Kernel

  private

  XSEL_OPTS = { primary: "-p", secondary: "-s", clipboard: "-b", }

  def xsel data = nil, sel: :primary
    XSEL_OPTS.has_key? sel or
      raise ScriptError, "Sorry, selection must be one of #{XSEL_OPTS.keys.join '/'}."
    if    ($xsel  ||= command? "xsel" ) then
      cmd = [ $xsel]
      cmd.push XSEL_OPTS[ sel]
      ci, co = "-i", "-o"
    elsif ($xclip ||= command? "xclip") then
      cmd = [ $xclip, "-selection", sel.to_s]
      ci, co = "-i", "-o"
    end
    cmd or raise ScriptError, "Sorry, Neither xsel nor xclip seem to be installed."
    if data then
      cmd.push ci
      cmd_write cmd, data
    else
      cmd.push co
      cmd_read  cmd
    end
  end
  def xsel! data, sel: :clipboard
    xsel data, sel: sel
  end

  def tmuxbuf data = nil, name: nil
    $tmux ||= command? "tmux"
    $tmux or raise ScriptError, "Sorry, TMux doesn't seem to be installed."
    args = []
    if name then
      args.push "-b", name
    end
    args.push "-"
    if data then
      cmd_write [ $tmux, "load-buffer", *args], data
    else
      cmd_read  [ $tmux, "save-buffer", *args]
    end
  end


  def command? cmd
    if cmd[ File::SEPARATOR] then
      cmd if File.executable? cmd
    else
      (ENV[ "PATH"].split File::PATH_SEPARATOR).each { |p|
        c = File.join p, cmd
        return c if File.executable? c
      }
      nil
    end
  end

  def cmd_write cmd, data
    case data
    when Enumerable then data = data.join $/
    when String     then nil
    else                 data = data.to_s
    end
    IO.popen cmd, "w" do |t| t.write data end
  end

  def cmd_read cmd
    IO.popen cmd, "r" do |t| t.read end
  end

end

