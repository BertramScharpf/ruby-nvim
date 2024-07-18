#
#  neovim/ruby_provider.rb  --  Plugin for :ruby* commands
#

require "neovim/handler"
require "neovim/remote_object"


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

  class Write
    class <<self
      def open client
        i = new client
        yield i
      ensure
        i.finish
      end
    end
    def initialize client
      @client = client
    end
    def print *args
      args.each { |a| write a.to_s }
      nil
    end
    def puts *args
      if args.empty? then
        write $/
      else
        args.each { |a|
          a = a.to_s
          write a
          write $/ unless a.end_with? $/
        }
      end
      nil
    end
    def flush
    end
  end

  class WriteStd < Write
    class <<self
      def redirect client
        open client do |i|
          old, $stdout = $stdout, i
          yield
        ensure
          $stdout = old
        end
      end
    end
  end

  class WriteOut < WriteStd
    def write *args
      args.each { |a|
        a.notempty? or next
        @client.out_write a
        @line_open = !(a.end_with? $/)
      }
      nil
    end
    def finish
      if @line_open then
        @client.out_write $/
        @line_open = nil
      end
    end
  end

  class WriteErr < Write
    class <<self
      def redirect client
        open client do |i|
          old, $stderr = $stderr, i
          yield
        ensure
          $stderr = old
        end
      end
    end
    def write *args
      args.each { |a|
        @rest ||= ""
        @rest << a
        while @rest =~ /#$// do
          @client.err_writeln $`
          @rest = $'
        end
      }
      nil
    end
    def finish
      if @rest.notempty? then
        @client.err_writeln @rest
        @rest = nil
      end
    end
  end

  class WriteBuf < WriteStd
    def write *args
      s = @rest||""
      args.each { |a|
        s << a
      }
      s = s.split $/, -1
      @rest = s.pop
      @client.put s, "l", true, true
      nil
    end
    def finish
      if @rest.notempty? then
        @client.put [@rest], "l", true, false
        @rest = nil
      end
    end
  end


  class DslProvider < DslBase

    TYPE = :script

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
            r.nil? or puts "#=> #{r.inspect}"
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

