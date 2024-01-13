require "wgz/version"
require "wgz/zabbix_client"
require "wgz/triggers"
require "wgz/caching_server"


module Wgz

  class << self

    def load_global_config(file)
      require "yaml"
      YAML.load IO.read File.expand_path file
    rescue Exception => e
      LOG.error "[app] Error loading config #{file}: #{e.message}."
      {}
    end

    def process(options = {})
      LOG.debug "[app] Options: #{options}"
      # Process triggers. Get from cmdline or from Zabbix
      #triggers = options[:triggers].empty? && $stdin.tty? ? Triggers.new : Triggers.new(options[:triggers])
      if (CONF[:wgz][:use_cache] rescue false) && options[:update]
        begin
          SocketRPC::Client.new((CONF[:wgz][:socket] rescue "/tmp/wgz.sock")).update_triggers :full => true
        rescue Exception => e
          LOG.warn "[app] Can't send update message to the cache server: #{e.message}"
          LOG.debug { e.backtrace.join($/) }
        end
      end
      triggers = Triggers.new($stdin.tty? ? nil : options[:triggers], options[:priority])
      cached = triggers.cached
      # Filter triggers
      triggers = triggers.
        filter_priority(options[:priority]).
        filter_status(options[:triggers_status]).
        filter_host(options[:host], options[:reverse]).
        filter_description(options[:filter], options[:reverse])
      # Select output format
      if options[:output] == :auto
        options[:output] = $stdout.tty? ? :table : :json
      end
      # Get ack if needed
      if (options[:output] == :table && $stdout.tty? || options[:issue]) && !cached
        triggers.get_last_ack_message!
      end
      # Filter by issue
      triggers = triggers.filter_message(options[:issue], options[:reverse]) if options[:issue]
      # Display output
      $stdout.puts triggers.public_send "to_#{options[:output].to_s}".to_sym
      # Acknowledge
      if options[:do_ack]
        if options[:host] || options[:filter]
          case options[:do_ack]
          when :reack
            triggers.reacknowledge!
          when String
            triggers.set_acknowledge!(options[:do_ack])
          end
        else
          LOG.warn "Reject to acknowledge tirggers without filters"
        end
      end
    end

    def run_server
      Signal.trap("INT") { exit }
      CachingServer.new((CONF[:wgz][:socket] rescue "/tmp/wgz.sock"))
    end
  end

end
