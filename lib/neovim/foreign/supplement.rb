#
#  neovim/foreign/supplement.rb  --  Additional useful Ruby functions
#

# The purpose of this is simply to reduce dependencies.

begin
  require "supplement"
rescue LoadError
  class NilClass ; def notempty? ;                      end ; end
  class String   ; def notempty? ; self unless empty? ; end ; end
  class Array    ; def notempty? ; self unless empty? ; end ; end
  class Array    ; def first= val ; self[ 0] = val ; end ; end
  class Array    ; def last=  val ; self[-1] = val ;
                    rescue IndexError ; a.push val ; end ; end
  class NilClass   ; def to_bool ; false ; end ; end
  class FalseClass ; def to_bool ; false ; end ; end
  class Object     ; def to_bool ; true  ; end ; end
  class <<Struct ; alias [] new ; end
  class Module
    def plain_name
      sep = "::"
      n = name.dup
      i = n.rindex sep
      n.slice! 0, i+sep.length if i
      n
    end
  end
  class String
    def axe n
      if n < length then
        e = "..."
        l = e.length
        if n > l then
          n -= l
        else
          l = 0
        end
        (slice 0, n) << "..."[0,l]
      else
        self
      end
    end
    def starts_with? oth ; o = oth.to_str ; o.length          if start_with? o ; end
    def ends_with?   oth ; o = oth.to_str ; length - o.length if end_with?   o ; end
    alias starts_with starts_with?
    alias ends_with   ends_with?
  end
  class Dir ; def entries! ; entries - %w(. ..) ; end ; end
end

