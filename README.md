# Ruby-Nvim

Ruby support for [Neovim](https://github.com/neovim/neovim).

Clean code, minimal dependecies, no frills, no wokeness.

*I would have written a shorter letter, but I did not have the time.* --
Blaise Pascal


## Installation

```shell
sudo gem uninstall neovim || true
sudo gem install nvim
```

You may prefer to also install the dependencies.  Yet, this is not
neccessary, as they are small and Ruby-Nvim includes a copy of them.

```shell
sudo gem install supplement mplight
```


## Usage


### Command, Function and Autoload Plugins

Put this into a new buffer:

```ruby
Neovim.plugin do |dsl|
  dsl.command :SetLine, nargs: 1 do |client,(str)|
    client.set_current_line str
  end
  dsl.function :Sum, nargs: 2, sync: true do |client,(x,y)|
    x + y
  end
  dsl.autocmd :BufEnter, pattern: "*.rb" do |client|
    client.command "echom 'Hello, Ruby!'"
  end
end
```

Then run these Vim commands:

```vim
w ++p ~/.config/nvim/rplugin/ruby/demo.rb
UpdateRemotePlugins

" Check the generated manifest file
split ~/.local/share/nvim/rplugin.vim
help remote-plugin-manifest
```

Open a new Neovim and see what happens:

```vim
e dummy.rb
SetLine some text
echo Sum(13,7)
```


### Calling the :ruby... Interface

The `:ruby...` commands and the `rubyeval()` function behave as descibed
in `:h ruby`.

Files mentioned in the global variable `g:ruby_require` will be loaded before
the first Ruby code will be run.

Additionally you can directly execute the buffers contents:

```vim
set number
```

```
 1 class C
 2   def f
 3     :F
 4   end
 5 end
 6 c = C.new
~
~
~
:1,6ruby |
```

The last value, if it is not `nil`, will be added through `#inspect` as
a comment.

```
 1 class C
 2   def f
 3     :F
 4   end
 5 end
 6 c = C.new
 7 #=> #<C:0x000001b347456478>
~
~
:
```

The classes and variables will be preserved and are available during the
next call.

```
 5 end
 6 c = C.new
 7 #=> #<C:0x00001fd2fd1f89d0>
 8 [ c.f, C]
~
~
~
:8ruby |
```

This results in:

```
 7 #=> #<C:0x00001fd2fd1f89d0>
 8 [ c.f, C]
 9 #=> [:F, C]
~
~
:
```

To inhibit the output of the last value, add a minus (`-`) to the
`:ruby|` call.

```
pp Regexp.constants
~
~
:.ruby |-
```

In this case, you may even omit the pipe (`|`) character.


#### Last return value

The anonymous variable `_` will hold the result
of the last evaluation.

```
 1 7*11*13
~
~
:%ruby |
```

Then this will work:

```
 1 7*11*13
 2 #=> 1001
 3 _ - 1
~
~
:3ruby |
```


#### Standard output

Output will be added to the buffer, too.

```
 1 puts "ba" + "na"*2
 2 print "hell"
 3 puts "o"
~
~
:1,3ruby |
```

Error output will be displayed on the command line,
highlighted by `ErrorMsg`.

```
 1 $stderr.puts "Oh, no!"
~
~
:%ruby |
```

This even applies to subprocesses. They won't mess up
the RPC communication.

```
 1 system *%w(ls -l)
 2 system *%w(ls nonexistent)
~
~
:%ruby |
```

Yet, you should avoid to use `fork` and `exec`, except when
you're absolutely sure what you're doing.


### List all API functions

To show a list of the API functions call something like this:

```
pp $vim.functions.sort
pp $vim.obj_classes.map { |c| [ c.type, ($vim.obj_functions c).sort] }.to_h
~
~
:%ruby |-
```

Deprecated functions and old functions not starting with `nvim_` will be
hidden. The full list of API functions can be obtained by a call to
`get_api_info`.

```
pp $vim.get_api_info
~
~
:.ruby |-
```

See the script `examples/dump_api` for a more elaborated and colorized
output.


### Calculator

Further, a simple number/cash summing tool is included.

```
Apples    :     3.99
Bananas   : 5 * 0.40          # multiplication
Oranges   :     3.59 - 10%    # percentage added (here subtracted)
Kiwi      :     0,40          # comma is allowed
Coconut   :     5,-           # empty decimal places
# !dot                        # dot forced now
Tangerines:     4.44
# !comma                      # result with comma
~
~
:%ruby +
```


### Modern rpcrequest() Calls

Put this into a new buffer:

```ruby
require "neovim"
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
```

Then enter these Vim commands:

```vim
w demo_remote.rb
let chan = jobstart(['ruby','demo_remote.rb'], { 'rpc': v:true })
call rpcrequest(chan, 'rb_add', 7)
call rpcrequest(chan, 'rb_raise')
call jobstop(chan)
```

If you prefer, you can also use a shebang line.

```ruby
#!/usr/bin/env ruby
require "neovim"
Neovim.start_remote do |dsl|
  # ... (as above)
end
```

Then enter these Vim commands:

```vim
w demo_remote.rb
!chmod +x %
let chan = jobstart('./demo_remote.rb', { 'rpc': v:true })
" proceed as above
```


### Logging and Debugging

Logging is a easy as this:

```shell
export NVIM_RUBY_LOG_LEVEL=all NVIM_RUBY_LOG_FILE=ruby.log
nvim +'ruby puts "hi"*10'
```

If the logfile isn't an absoulte path and doesn't start with `"./"`,
it will be relative to Neovim's `stdpath("log")`.

To show the log levels, simply run in Neovim:

```vim
ruby puts Neovim::Logging::LEVELS.keys
```

If you are inside a [Tmux](https://tmux.github.io), you might prefer to trace
the colored log in a split window.

```shell
tmux split-window -fhd 'echo -e "\e[33m==== $$ ==== `tty` ====\e[m" ; ln -sf `tty` /tmp/tmux-`id -u`/debug ; exec cat >/dev/null 2>&1'
export NVIM_RUBY_LOG_LEVEL=all NVIM_RUBY_LOG_FILE=/tmp/tmux-`id -u`/debug

examples/demo_attach

nvim +'ruby puts "hi"*10'
```

You may start an interactive session and control a running Neovim through it.
Open Neovim specifying the `--listen` option

```shell
nvim --listen /path/to/some.sock
```

or ask the running Neovim for its server name.

```vim
echo v:servername
```

Then connect to it.  This requires the [Intar](https://github.com/BertramScharpf/ruby-intar) gem.

```
$ intar -r neovim/remote
main:0:001> include Neovim
=> Object
main:0:002> Remote.start_client ConnectionUnix, "/path/to/some.sock" do |c|&
main:1:001> c.command "e /etc/passwd"
main:1:002> b = c.get_current_buf
=> #<Neovim::Buffer:400 1>
main:1:003> b[1]
=> ["root:*:0:0:Charlie &:/root:/bin/sh"]
main:1:004> \q!!
```


#### Miscellaneous Tools

Put text into an X selection or a TMux register.

```vim
let g:ruby_require = "neovim/tools/copy"
'<,'>ruby xsel $lines
'<,'>ruby xsel! $lines
'<,'>ruby tmuxbuf $lines
```

Make a hex dump.

```vim
ruby <<EOT
  require "neovim/foreign/xxd"
  bn = $curbuf.get_name
  $vim.command :new
  File.open bn do |b| Xxd::Dump.new.run b do |l| $vim.put [l], "l", false, true end end
EOT
```


## Copyright

  * (C) 2024 Bertram Scharpf <software@bertram-scharpf.de>
  * License: [BSD-2-Clause+](./LICENSE)

