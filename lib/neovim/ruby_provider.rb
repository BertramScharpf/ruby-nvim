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

  Buffer = ::Neovim::Buffer
  class <<Buffer
    def current ; $vim.get_current_buf ; end
    def count   ; $vim.list_bufs.size  ; end
    def [] i    ; $vim.list_bufs[ i]   ; end
  end

  Window = ::Neovim::Window
  class <<Window
    def current ; $vim.get_current_win                    ; end
    def count   ; $vim.get_current_tabpage.list_wins.size ; end
    def [] i    ; $vim.get_current_tabpage.list_wins[ i]  ; end
    self
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
      rescue Exception
        msg = $!.to_s
        if msg =~ /\A.*?:(\d+):\s*/ then
          line, msg = $1, $'
        else
          line = $@.first[ /:(\d+):in\b/, 1]
        end
        client.message_err "Ruby #{$!.class}:#{line}: #{msg}"
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
        $range, $lines = range, (Lines.new client, range)
        yield $lines
      end
    ensure
      $range, $lines = nil, nil
    end

    def plugin_provider &block
      run_dsl DslProvider, &block
    end

  end

  plugin_provider do |dsl|

    dsl.setup do |client|
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
      if code =~ /\A\|?(-)?\z/ then  # | is a workaround because Neovim doesn't allow empty code (the ultimate Quine).
        no_out = $1
        set_globals client, fst..lst do |lines|
          client.command "#{lst}"
          WriteBuf.redirect client do
            r = begin
              script_binding.eval lines.to_s, "ruby_run"
            rescue Exception
              $@.pop until $@.empty? or $@.last.ends_with? ":in `empty_binding'"
              raise unless $rescue
              $!
            end
            unless no_out or r.nil? then
              script_binding.local_variable_set :_, r
              puts "#=> #{r.inspect}"
            end
          end
        end
      elsif code == "+" then
        client.command "#{lst}"
        set_globals client, fst..lst do |lines|
          WriteBuf.redirect client do
            require "neovim/tools/calculator"
            @calc ||= Calculator.new
            @calc.reset!
            w = 0
            lines.each { |l|
              l.length.tap { |g| w = g if g > w }
              @calc.add l
            }
            puts "-"*w
            puts @calc.result
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
      if path =~ /<(.*)>\z/ then
        set_global_client client do
          require $1
        end
      else
        set_globals client, fst..lst do ||
          r = File.read path
          script_binding.eval r, "ruby_file #{path}"
        end
        nil
      end
    end

    # This is called by the +:rubydo+ command.
    dsl.rpc :ruby_do_range do |client,fst,lst,code|
      set_globals client, fst..lst do |lines|
        lines.map! do |l,i|
          (script_binding.eval 'proc do |l,i| $_, $. = l, i end').call l, i
          script_binding.eval code, "ruby_do_range"
          script_binding.eval '$_'
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

