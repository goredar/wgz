require "wgz/socket_rpc"

module Wgz
  class CachingServer < SocketRPC::Server
    def initialize(*args)
      @update_mutex = Mutex.new
      @cache = Triggers.new []
      @update_interval = ((CONF[:wgz][:update_interval] rescue 60) || 60)
      @update_counter = 0
      Thread.new do
        loop do
          if @update_counter % 10 == 0
            LOG.info "[cache] Perfom full update"
            update_triggers :full => true
          else
            update_triggers
          end
          @update_counter += 1
          sleep @update_interval
        end
      end
      super
    end
    def get_cached_triggers
      raise "stale data" if (Time.now - @cache.timestamp).to_i > ((CONF[:wgz][:stale_threshold] rescue 120) || 120)
      @cache.to_a
    end
    def update_triggers(args = {})
      args[:full] ||= false
      if @update_mutex.locked?
        # Already updating - wait and return
        LOG.warn "[cache] request to update ignored: already updating"
        sleep 0.1 while @update_mutex.locked?
      else
        @update_mutex.synchronize do
          @cache.update! :priority => 0, :full => args[:full]
          @cache.get_last_ack_message!
          LOG.success "[cache] updated at #{@cache.timestamp}"
        end
      end
    rescue Exception => e
      LOG.error "[cache] faild to update: #{e.message}"
      LOG.debug "[cache] #{e.backtrace.join($/)}"
    end
  end
end
