module SocketRPC
  module RPC
    def remote_call(method, *args)
      remote_send :method => method, :args => args
      response = receive
      response[:status] == 'OK' ? response[:result] : raise(response[:message])
    end
    def process(object)
      request = receive
      begin
        remote_methods = object.remote_methods
      rescue Exception => e
        remote_send :status => 'ERROR', :message => 'invalid remote object'
        return
      end
      if remote_methods.include?(request[:method])
        begin
          remote_send :status => 'OK', :result => object.public_send(request[:method], *request[:args])
        rescue Exception => e
          remote_send :status => 'ERROR', :message => e.message
        end
      else
        remote_send :status => 'ERROR', :message => 'remote method missing'
      end
    end
    def remote_send(message, delimiter = nil)
      require 'securerandom'
      delimiter ||= SecureRandom.hex(16)
      puts delimiter
      self.puts Marshal.dump(message)
      puts delimiter
    end
    def receive
      delimiter = self.readline
      string = ''
      loop do
        line = self.readline
        break if line == delimiter
        string += line
      end
      Marshal.load string
    end
  end

  class Server
    def initialize(socket, object = nil)
      require 'socket'
      object = object.nil? ? self : object
      Socket.unix_server_loop(socket) do |client, _|
        Thread.new do
          begin
            class << client; include SocketRPC::RPC; end
            client.process(object)
          ensure
            client.close
          end
        end
      end
    end
    def remote_methods
      @remote_methods ||= self.methods - Object.methods
    end
  end

  class Client
    def initialize(socket)
      require 'socket'
      @server = Socket.unix(socket)
      class << @server; include SocketRPC::RPC; end
    end
    def close
      @server.close
    end
    def method_missing(method, *args)
      @server.remote_call method, *args
    end
  end
end
