#
#  neovim/output.rb  --  Output to Neovim
#



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
    def initialize *args
      super
      @lines = [""]
    end
    def write *args
      s = @lines.pop
      args.each { |a| s << a }
      s.split $/, -1 do |l| @lines.push l end
      nil
    end
    def finish
      @lines.last.notempty? or @lines.pop
      @client.put @lines, "l", true, true
    end
  end

end

