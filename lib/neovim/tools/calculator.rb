#
#  neovim/tools/calculator.rb  --  Simple calculator
#

require "supplement"
require "bigdecimal"


module Neovim

  class Calculator

    def result
      r = @result.round @decs
      case r
      when BigDecimal then
        r = r.to_s "F"
        r.sub! /(?:(\.)([0-9]+))?\z/ do
          (@sep||$1) + ($2.to_s.ljust @decs, "0")
        end
      when Integer    then
        r = r.to_s
      end
      r
    end

    def reset!
      @result = nil
    end

    def decs= d ; @decs = Integer d ; end

    def dot!   ; @sep, @grp = ".", "," ; end
    def comma! ; @sep, @grp = ",", "." ; end
    def dot?   ; @sep == "." ; end
    def comma? ; @sep == "," ; end

    def add line
      line = line.chomp
      line.slice! /#.*/
      if $& =~ /!(\w+)/ then
        case $1
          when "c", "comma", "k", "komma" then comma!
          when "d", "dot", "p", "point"   then dot!
          when /\A\d+\z/                  then @decs = $1.to_i
        end
      end
      line.slice! /^.*:/
      line.strip!
      line.notempty? or return

      products = []
      line.split /(?:[;|&]|\s+(?:[,+-]\s+)?)/ do |p|
        products.push [ (split_products p), $& == "-"]
      end

      minus = false
      products.each { |p,nm|
        if not @result then @result =  p
        elsif minus    then @result -= p
        else                @result += p
        end
        minus = nm
      }
      @result
    end

    private

    def split_products p
      nums = []
      p.split /[*\/]/ do |n|
        nums.push [ (parse_number n), $& == "/"]
      end

      inv = false
      prod = nil
      nums.each  { |n,ni|
        if not prod then prod =  n
        elsif inv   then prod /= n
        else             prod *= n
        end
        inv = ni
      }
      @prev = prod
    end

    def parse_number n
      n.strip!
      if n =~ %r/ *%\z/ then
        @prev * (BigDecimal $`) / 100
      else
        comma! if not @sep and n =~ /\d,\d/
        case @sep
        when "," then n.gsub! @grp, "_" ; n.sub! @sep, "."
        when "." then n.gsub! @grp, "_"
        end
        if    n =~ /\.-/ then
          n = $`
          @decs ||= 2
        elsif n =~ /\.(\d*)/ then
          d = $1.length
          @decs = d if not @decs or @decs < d
        end
        @decs.nonzero? ? (BigDecimal n) : (Integer n)
      end
    end

  end

end

