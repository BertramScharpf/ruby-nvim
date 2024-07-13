#
#  demo.rb  --  Demo plugin
#


Neovim.plugin do |dsl|

  dsl.command :SetLine, nargs: 1 do |client,(str)|
    client.set_current_line str
  end

  dsl.command :Fail, nargs: 0 do |client|
    raise "ouch!"
  end

  dsl.function :Sum, nargs: 2, sync: true do |client,x,y|
    x + y
  end

  dsl.function :Fail do |client|
    raise "ouch!"
  end

  dsl.function :Other, nargs: 2, range: true, eval: "strftime('%s')" do |client,(x,y),range,evaled|
    r = "<<<#{x}---#{y}===#{range}---#{evaled}>>>"
    client.buf_set_lines 0, 0, 0, false, [r.inspect]
    r
  end

  dsl.autocmd :BufEnter, pattern: "*.rb" do |client|
    client.command "echom 'Hello, Ruby!'"
  end

end

