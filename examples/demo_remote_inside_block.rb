#!/usr/bin/env ruby

#
#  examples/demo_remote_inside_block.rb  --  Demo for plain handlers
#

require "neovim"


if $stdin.tty? then
  puts <<~EOT
    " How to run this from inside Neovim:
    let chan = jobstart(['ruby','#$0', 'counter.log', 100], { 'rpc': v:true })
    echo rpcrequest(chan, 'rb_add', 7)
    echo jobstop(chan)
  EOT
  exit 1
end


logname, counter = *$*
logname ||= "counter.log"
counter = counter.to_i

File.open logname, "w" do |log|

  log.puts "I was called with: #{$*.inspect}"
  log.flush

  Neovim.start_remote do |dsl|

    dsl.register_handler "rb_add" do |client,n|
      counter += n
      client.command "echo 'Counter value now is: '..#{counter}..'.'"
      log.puts "Counter: #{counter}"
      log.flush
      nil
    end

  end

ensure
  log.puts "Bye from counter at #{counter}."
  log.flush

end

