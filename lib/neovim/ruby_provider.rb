#
#  neovim/ruby_provider.rb  --  Plugin for :ruby* commands
#

require "neovim/handler"
require "neovim/remote_object"
require "neovim/output"


class Object
  # Poor, poor RubyGems is polluting the global namespace.
  # see <https://github.com/rubygems/rubygems/pull/7200>
  def empty_binding
    binding
  end
end


# The VIM module as documented in ":h ruby".
module Vim

  class Buffer < ::Neovim::Buffer
    class <<self
      def current ; $vim.get_current_buf ; end
      def count   ; $vim.list_bufs.size  ; end
      def [] i    ; $vim.list_bufs[ i]   ; end
    end
  end

  class Window < ::Neovim::Window
    class <<self
      def current ; $vim.get_current_win                    ; end
      def count   ; $vim.get_current_tabpage.list_wins.size ; end
      def [] i    ; $vim.get_current_tabpage.list_wins[ i]  ; end
    end
  end

  class <<self
    def message str   ; $vim.message str   ; end
    def set_option *args, **kwargs ; $vim.set_option *args, **kwargs ; end
    alias set_options set_option
    def command arg   ; $vim.command arg   ; end
    def evaluate expr ; $vim.evaluate expr ; end
  end

  ::VIM = self

end




module Neovim

  class DslProvider < DslBase

    TYPE = :script

    def initialize source
      super *[]
    end

    def setup &block
      add_setup_block &block
    end

    def setup_autocmd event, fn, *args
      add_setup_block do |client|
        a = [ client.channel_id, "'#{fn}'", *args].join ", "
        client.command "autocmd #{event} * call rpcrequest(#{a})"
      end
    end

    def updater name, &block
      add_handler nil, name, &block
    end

    def rpc name
      add_handler nil, name do |client,*args|
        WriteOut.redirect client do
          WriteErr.redirect client do
            yield client, *args
          end
        end
      rescue ScriptError, StandardError
        line = $@.first[ /:(\d+):/, 1]
        client.err_writeln "Ruby #$! (#{$!.class}), line #{line}"
      end
    end

  end

  class <<self

    def set_global_client client
      $vim = client
      yield
    ensure
      $vim = nil
    end

    def set_globals client, range
      set_global_client client do
        lines = get_lines client, range
        $range, $lines = range, lines
        yield lines
      end
    ensure
      $range, $lines = nil, nil
    end

    def get_lines client, range
      client.buf_get_lines 0, range.begin-1, range.end, true
    end

    def plugin_provider &block
      run_dsl DslProvider, &block
    end

    def build_sum lines
      require "bigdecimal"
      sum = BigDecimal 0
      prev, decs = 0, 0
      sep = "."
      lines.each { |l|
        l.slice! /^.*:/
        l.slice! /#.*/
        l = l.split /(?:\+\s+|\|)/
        l.map! { |m|
          m.strip!
          if m =~ %r/ *%\z/ then
            prev * (BigDecimal $`) / 100
          else
            m = m.split "*"
            m.map! { |n|
              n.sub! /,/ do sep = $& ; "." end
                n.sub! /\.(?:-+|([0-9]+))/ do
                  if $1 then
                    d = $1.length
                    decs = d if decs < d
                    ".#$1"
                  else
                    decs = 2
                    nil
                  end
                end
                BigDecimal n
            }
            prev = m.inject do |p,e| p*e end
          end
        }
        sum = l.inject sum do |s,e| s+e end
      }
      sum = sum.round decs
      case sum
      when BigDecimal then
        sum = sum.to_s "F"
        sum.sub! /(?:\.([0-9]+))?\z/ do
          sep + ($1.to_s.ljust decs, "0")
        end
      when Integer    then
        sum = sum.to_s
      end
      sum
    end

  end

  plugin_provider do |dsl|

    dsl.setup do |client|
      r = client.get_var "ruby_require" rescue nil
      case r
      when Array then r = r.notempty?
      when nil   then nil
      else            r = [r]
      end
      if r then
        WriteOut.redirect client do  # Protect the RPC interface against erroneous output.
          r.each do |l|
            require l
          rescue LoadError
            client.err_writeln + $!.to_s
          end
        end
      end
      $curbuf = client.get_current_buf
      $curwin = client.get_current_win
    end

    dsl.setup_autocmd :BufEnter, "ruby_bufenter"
    dsl.updater :ruby_bufenter do |client|
      $curbuf = client.get_current_buf
    end

    dsl.setup_autocmd :WinEnter, "ruby_winenter"
    dsl.updater :ruby_winenter do |client|
      $curbuf = client.get_current_buf
      $curwin = client.get_current_win
    end

    dsl.setup_autocmd :DirChanged, "ruby_chdir", "v:event"
    dsl.updater :ruby_chdir do |_,event|
      Dir.chdir event[ "cwd"]
    end


    script_binding = TOPLEVEL_BINDING.eval "empty_binding"

    # This is called by the +:ruby+ command.
    dsl.rpc :ruby_execute do |client,code,fst,lst|
      code.rstrip!
      if !code.notempty? or code == "|" then  # Workaround because Neovim doesn't allow empty code (the ultimate Quine)
        set_global_client client do
          client.command "#{lst}"
          code = (get_lines client, fst..lst).join $/
          WriteBuf.redirect client do
            r = script_binding.eval code, "ruby_run"
            unless r.nil? then
              script_binding.local_variable_set :_, r
              puts "#=> #{r.inspect}"
            end
          end
        end
      elsif code == "+" then
        client.command "#{lst}"
        set_globals client, fst..lst do |lines|
          WriteBuf.redirect client do
            s = build_sum lines
            puts "-"*(s.length + 4)
            puts s
          rescue
            puts "Error: #$! (#{$!.class})"
          end
        end
      else
        set_globals client, fst..lst do ||
          script_binding.eval code, "ruby_execute"
        end
      end
      nil
    end

    # This is called by the +:rubyfile+ command.
    dsl.rpc :ruby_execute_file do |client,path,fst,lst|
      set_globals client, fst..lst do ||
        r = File.read path
        script_binding.eval r, "ruby_file #{path}"
      end
      nil
    end

    # This is called by the +:rubydo+ command.
    dsl.rpc :ruby_do_range do |client,fst,lst,code|
      set_globals client, fst..lst do |lines|
        i = fst
        lines.each do |l|
          h = l.hash
          (script_binding.eval 'proc do |l,i| $_, $. = l, i end').call l, i
          script_binding.eval code, "ruby_do_range"
          m = script_binding.eval '$_'
          if m.hash != h then
            m = m.lines
            m.each { |x| x.chomp! }
            client.buf_set_lines 0, i-1, i, true, m
            i += m.length
          else
            i += 1
          end
        end
      end
      nil
    ensure
      script_binding.eval '$_, $. = nil, 0'
    end

    # This is called by the +rubyeval()+ function.
    dsl.rpc :ruby_eval do |client,code|
      set_global_client client do
        script_binding.eval code, "ruby_eval"
      end
    end

  end

end

