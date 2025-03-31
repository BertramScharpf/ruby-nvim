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
            a.end_with? $/ or write $/
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
    def initialize *args
      super
      @str = ""
    end
    def write *args
      args.each { |a| @str << a.to_s }
      loop do
        l, r = @str.split $/, 2
        r or break
        write_line l
        @str = r
      end
      nil
    end
    def finish
      if @str.notempty? then
        write_line @str
        @str = nil
      end
    end
  end

  class WriteOut < WriteStd
    private
    def write_line l
      @client.message l
    end
  end

  class WriteErr < WriteStd
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
    private
    def write_line l
      @client.message_err l
    end
  end

  class WriteBuf < WriteStd
    def initialize *args, whole: nil, top: nil
      super
      @lines = []
      @whole, @top = whole, top
    end
    def finish
      super
      if @whole then
        @client.buf_set_lines 0, 0, -1, true, @lines
      else
        @client.put @lines, "l", true, !@top
      end
    end
    private
    def write_line l
      @lines.push l
    end
  end

end

