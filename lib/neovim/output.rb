#
#  neovim/output.rb  --  Output to Neovim
#


module Kernel

  module_function def system *cmd
    ro, wo = IO.pipe
    re, we = IO.pipe
    child = fork do
      STDIN.close
      ro.close ; STDOUT.reopen wo ; wo.close
      re.close ; STDERR.reopen we ; we.close
      exec *cmd
    end
    wo.close
    we.close
    h = { ro => $stdout, re => $stderr, }
    until h.empty? do
      h.keys.each { |r|
        if r.eof? then
          r.close
          h.delete r
        else
          h[ r].puts r.readline
        end
      }
    end
    Process.waitpid child
    $?.success?
  end

end


module Neovim

  class Write
    class <<self
      def open *args, **kwargs
        i = new *args, **kwargs
        yield i
      ensure
        i.finish
      end
    end
    def initialize client, *rest
      @client = client
    end
    def << arg
      write arg.to_s
      self
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
          case a
          when Array then
            a.each { |e|
              puts e
            }
          else
            a = a.to_s
            write a
            write $/ unless a.end_with? $/
          end
        }
      end
      nil
    end
    def flush
    end
  end

  class WriteStd < Write
    class <<self
      def redirect *args, **kwargs
        open *args, **kwargs do |i|
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
        a = a.to_s
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
      def redirect *args, **kwargs
        open *args, **kwargs do |i|
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
        @rest << a.to_s
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
    def initialize *args, whole: nil, top: nil
      super
      @lines, @last = [], ""
      @whole, @top = whole, top
    end
    def write *args
      args.each { |a| @last << a.to_s }
      loop do
        n, r = @last.split $/, 2
        r or break
        @lines.push n
        @last = r
      end
      nil
    end
    def finish
      if @last.notempty? then
        @lines.push @last
        @last = nil
      end
      if @whole then
        @client.buf_set_lines 0, 0, -1, true, @lines
      else
        @client.put @lines, "l", true, !@top
      end
    end
  end

end

