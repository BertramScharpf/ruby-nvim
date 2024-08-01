#
#  neovim/output.rb  --  Output to Neovim
#



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
    def initialize *args, whole: nil, top: nil
      super
      @lines = [""]
      @hole, @top = whole, top
    end
    def write *args
      s = @lines.pop
      args.each { |a| s << a }
      s.split $/, -1 do |l| @lines.push l end
      nil
    end
    def finish
      @lines.last.notempty? or @lines.pop
      if @whole then
        @client.buf_set_lines 0, 0, -1, true, @lines
      else
        @client.put @lines, "l", true, !@top
      end
      @lines = nil
    end
  end

end

