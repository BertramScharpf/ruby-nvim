#
#  neovim/connection.rb  --  Connections
#

require "neovim/logging"
require "neovim/client"
require "neovim/info"


module Neovim

  class Connection < MPLight::Types

    include Logging

    include MPLight::Packer, MPLight::Unpacker

    attr_reader :client

    def initialize rd, wr
      super
      default_to_string!
      init_input  rd
      init_output wr
      @errors = {}
    end

    def additional_data ; [ *super, @client] ; end


    def error id
      @errors[ id] || "Error #{id}"
    end


    def start comm
      comm.notify :nvim_set_client_info, comm.client_name, INFO.version_h, comm.client_type, comm.client_methods||{}, INFO.attributes
      channel_id, api_info = *(comm.request :nvim_get_api_info)
      @client = Client.new comm, channel_id
      prefixes = {}
      api_info[ "types"].each do |type,info|
        type = type.to_sym
        prefixes[ type] = info[ "prefix"]
        register_type type, info[ "id"]
      end
      @client.add_functions api_info[ "functions"], prefixes
      api_info[ "error_types"].each { |type,info|
        register_error type, info[ "id"]
      }
      if api_info["version"]["api_level"] < 13 then
        log :warn, "Using nvim_err_writeln() which is deprecated in since Neovim 0.11.0"
        @client.define_singleton_method :message_err do |msg|
          call_api :err_writeln, msg
        end
      end
      nil
    end

    private

    def register_type type, id
      klass = Neovim.const_get type
      klass or raise "Class #{type} is not defined."
      klass < RemoteObject or raise "Class #{klass} is not a descendant of RemoteObject."
      log :debug2, "Registering type", type: type, id: id
      register id, klass
    end

    def register_error id, type
      @errors[ id] = type
    end

  end


  class ConnectionTcp < Connection
    class <<self
      def open_files host, port, timeout: nil
        due = Time.now + timeout if timeout
        require "socket"
        begin
          TCPSocket.open host, port do |socket|
            due = nil
            yield (new socket, socket)
          end
        rescue Errno::ECONNREFUSED
          if due then
            sleep 0.1
            retry
          end
        end
      end
    end
  end

  class ConnectionUnix < Connection
    class <<self
      def open_files path, timeout: nil
        due = Time.now + timeout if timeout
        require "socket"
        begin
          UNIXSocket.open path do |socket|
            due = nil
            yield (new socket, socket)
          end
        rescue Errno::ENOENT
          if due then
            sleep 0.1
            retry
          end
        end
      end
    end
  end

  class ConnectionChild < Connection

    class <<self

      def open_files *argv
        eb = "--embed"
        argv.unshift eb unless argv.include? eb
        argv.unshift path
        IO.popen argv, "r+" do |io|
          Process.detach io.pid
          yield (new io, io)
        end
      end

      def path
        ENV[ "NVIM_EXECUTABLE"].notempty? || "nvim"
      end

      def version
        IO.popen [ path, "--version"] do |io|
          io.gets[ /\ANVIM +v?(.+)/, 1]
        end
      end

      def stdpath what
        cmd = [ path, "--headless", ]
        cmd.push "-u", "NONE"
        cmd.push "-c", "echo stdpath(#{what.to_s.inspect})"
        cmd.push "-c", "q"
        (pipe_stderr cmd)&.tap { |x| x.chomp! }
      end

      private

      def pipe_stderr cmd
        re, we = IO.pipe
        fork do
          re.close ; $stderr.reopen we ; we.close
          exec *cmd
        end
        we.close
        re.read
      end

    end

  end

  class ConnectionStdio < Connection
    class <<self
      def open_files *argv
        yield (new $stdin, $stdout)
      end
    end
  end

end

