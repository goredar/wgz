module Wgz
  class ZabbixClient

    def initialize(args = {})
      require 'oj'
      require 'curb'
      @server = (args[:server] || (CONF[:zabbix][:url].chomp('/') rescue "https://zabbix.acme.net")) + "/api_jsonrpc.php"
      @curl = Curl::Easy.new(@server)
      @curl.timeout = 15
      @curl.ssl_verify_peer = false
      @curl.headers['Accept'] = 'application/json'
      @curl.headers['Content-Type'] = 'application/json'
      @curl.headers['Api-Version'] = '2.2'
      @token = nil
      @token = user_login(
        "user" => (args[:user] || (CONF[:user] rescue nil)),
        "password" => (args[:pass] || (CONF[:pass] rescue nil))
      )
      LOG.debug "[zabbix] authorized to zabbix"
    end

    def token
      @token
    end

    def triggers(args = {})
      trigger_get({
                    "active" => true,
                    "monitored" => true,
                    "skipDependent" => true,
                    "only_true" => true,
                    "expandComment" => true,
                    "expandDescription" => true,
                    "expandExpression" => true,
                    "filter" => { "value" => 1},
                    "selectHosts" => %w(host maintenance_status),
                    "selectItems" => %w(name lastvalue value_type key_),
                    "selectLastEvent" => %w(acknowledged),
                    "output" => %w(description lastchange priority url comments expression),
                    "sortfield" => "lastchange",
                    "sortorder" => "DESC",
                  }.merge args).tap { |t| LOG.debug "[zabbix] got #{t.nil? ? 0 : t.count} triggers" }
    end

    def events(event_ids = nil)
      return [] if event_ids.is_a?(Array) && event_ids.empty?
      event_get({
                 "eventids" => event_ids,
                 "select_acknowledges" => %w(alias message),
                 }).tap { |e| LOG.debug "[zabbix] got #{e.nil? ? 0 : e.count} ivents by id (#{event_ids})" }
    end

    def events_by_object(object_id = nil)
      return [] unless object_id
      event_get({
                 "objectids" => object_id,
                 "acknowledged" => true,
                 "select_acknowledges" => %w(alias message),
                 #"limit" => object_id.is_a?(Array) ? object_id.size : 1
                 "sortfield" => ["clock", "eventid"],
                 "sortorder" => "DESC",
                 "limit" => 10,
                }).tap { |e| LOG.debug "[zabbix] got #{e.nil? ? 0 : e.count} ivents by object (#{object_id})" }
    end

    def acknowledge(event_ids = nil, message = nil)
      return unless event_ids
      return unless message
      return if event_ids.is_a?(Array) && event_ids.empty?
      event_acknowledge({
                         "eventids" => event_ids,
                         "message" => message,
                        })
    end

    def method_missing(method, *args)
      if args.size <= 1
        jrpc_call method: method.to_s.split('_').join('.'), params: args.first
      else
        super
      end
    end

    private

    def jrpc_call(args = {})
      req = {
        "jsonrpc" => "2.0",
        "method" => args[:method],
        "params" => args[:params],
        "id" => rand(2 ** 16),
        "auth" => @token,
      }
      @curl.http_post Oj.dump req
      res = Oj.load(@curl.body_str) rescue (LOG.error("[jrpc] Invalid responce: #{@curl.body_str.split.join}"); return nil)
      if res["error"]
        LOG.error "[jrpc] Jrpc request failed: #{res["error"]}"
        nil
      else
        res["result"]
      end
    rescue Exception => e
      LOG.error "[jrpc] Request to '#{@server}' failed: #{e.message}"
      raise e
    end

  end
end
