#
#  neovim/tools/summation.rb  --  Summation of numbers
#

require "supplement"
require "bigdecimal"


module Neovim

  class Summation

    class Error < StandardError ; end

    class Ratchet
      attr_reader :value
      def initialize ; @value = 0 ; end
      def push val ; @value = val if val > @value ; end
    end

    attr_reader :count

    def initialize nums
      @nums = nums || Numbers
      @result = @nums.value "0"
      @count = 0
      @indent, @width = Ratchet.new, Ratchet.new
    end

    def add line
      l = line.dup
      @count += 1
      @width.push l.length
      l.slice! %r/(?:^|\s+)#.*/
      if l.slice! %r/^.*?:/ then
        @indent.push $&.length
      end
      percent = l.slice! /\S+%/
      val, factor, = l.split
      val =
        if val then
          @nums.value val
        else
          @prev or raise "No previous value"
        end
      if factor then
        val *= @nums.factor factor
      end
      if percent then
        if percent =~ /\A\\/ then
          val = @nums.percent_split val, $'
        else
          val = @nums.percent_of val, percent
        end
      end
      val = @nums.adjust val
      @result += val
      @prev = val
      nil
    rescue
      raise
      raise Error, "#$! in #@count:#{line}"
    end

    def sep
      "-" * @width.value
    end

    def result
      r = " " * @indent.value
      r << (@nums.format @result).to_s
    end

    class Numbers
      class <<self
        def value str
          BigDecimal str
        end
        def factor str
          BigDecimal str
        end
        def percent_of val, str
          val * (percent str)
        end
        def percent_split val, str
          val / ((percent str) + 1)
        end
        def adjust val
          BigDecimal === val or raise Error, "Internal error with #{val}"
          val
        end
        def format val
          val.to_s "F"
        end
        private
        def percent str
          str.slice! /%\z/
          (BigDecimal str) / 100
        end
      end
    end

    class Commercial < Numbers
      class <<self
        def adjust val
          super.round 2
        end
        def format val
          r = val.to_s "F"
          r =~ /\.(\d?)\z/ and r << ("0" * (2-$1.length))
          r
        end
        def percent_split val, str
          super
          # Strictly spoken, this is not correct.
          # Some values will be rounded downwards, some upwards.
          #
          # 50.14 / 1.19  #=> 42.134453781512605 -> 42.13
          # 42.13 * 1.19  #=> 50.1347 -> 50.13   # this one will be returned
          # 42.14 * 1.19  #=> 50.1466 -> 50.15
          #
          # 50.07 / 1.19  #=> 42.075630252100844 -> 42.08
          # 42.07 * 1.19  #=> 50.0633 -> 50.06
          # 42.08 * 1.19  #=> 50.0752 -> 50.08   # this one will be returned
        end
      end
    end

    class Human < Numbers
      PREFIXES     = " kMGTPEZY"
      PREFIXES_ALT = " K"
      KB = 1024
      class <<self
        def value str
          prefix = str.slice! /[a-zA-Z]\s*\z/
          if prefix then
            t =   PREFIXES    .index prefix
            t ||= PREFIXES_ALT.index prefix
          end
          str.sub! ",", "."
          r = super str
          t&.times { r *= KB }
          r.to_i
        end
        def adjust val
          val.to_i
        end
        def format val
          n, s = 0, val.to_f
          while s >= KB do s /= KB ; n += 1 end
          format = n.zero? ? "%4d  " : "%6.1f"
          format << "%c"
          format % [ s, PREFIXES[ n]||"?"]
        end
      end
    end

  end

end

