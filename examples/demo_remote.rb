#!/usr/bin/env ruby

#
#  demo_remote.rb  --  Demo for plain handlers
#

require "neovim"


if $stdin.tty? then
  puts <<~EOT
    # How to run this from inside Neovim:
    let chan = jobstart(['ruby','#$0'], { 'rpc': v:true })
    call rpcrequest(chan, 'rb_add', 7)
    call rpcrequest(chan, 'rb_raise')
    call jobstop(chan)
  EOT
  exit 1
end


counter = 0

Neovim.start_remote do |dsl|

  dsl.register_handler "rb_add" do |client,n|
    counter += n
    client.command "echo 'Counter value now is: '..#{counter}..'.'"
  end

  dsl.register_handler "rb_raise" do |client|
    raise "Ouch!"
  end

end

