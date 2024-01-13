module Wgz
  class Triggers

    attr_reader :timestamp, :cached

    require "colorize"
    PRIORITY = ["NC(0)".light_green, "Inf(1)".green, "Warn(2)".yellow, "Aver(3)".red, "High(4)".on_red, "Dis(5)".on_light_red]
    PRIORITY_NC = %w(Not_classified Information Warning Average High Disaster)
    PRIORITY_COMPACT = ["N".light_green, "I".green, "W".yellow, "A".red, "H".on_red, "D".on_light_red]
    STATUS = { ack: "ack".green, una: "una".red, mnt: "mnt".yellow }
    MAX_PRIORITY = PRIORITY.count - 1

    def initialize(triggers = nil, priority = 1)
      if !triggers.is_a?(Array)
        # Try to use cache
        if (CONF[:wgz][:use_cache] rescue false)
          begin
            @triggers = SocketRPC::Client.new((CONF[:wgz][:socket] rescue "/tmp/wgz.sock")).get_cached_triggers
            @cached = true
          rescue Exception => e
            LOG.warn "[app] Error communicating with cache server at #{(CONF[:wgz][:socket] rescue "/tmp/wgz.sock")}: #{e.message}"
            LOG.debug { e.backtrace.join($/) }
            update! :priority => priority
          end
        # Process on your own
        else
          update! :priority => priority
        end
      else
        @triggers = triggers
      end
      @jira_url = CONF[:jira][:url].chomp('/') rescue "https://jira.acme.net"
      @zabbix_url = CONF[:zabbix][:url].chomp('/') rescue "https://zabbix.acme.net"
    end

    def connect_to_zabbix
      @@zbx ||= ZabbixClient.new
    end

    def update!(args = {})
      args[:priority] ||= 1
      args[:full] ||= false
      connect_to_zabbix
      triggers = @@zbx.triggers({ "min_severity" => args[:priority] })
      if triggers
        triggers.map! do |trigger|
          host = trigger.delete("hosts").first || { "hostid"=>"0", "host"=>"unknown", "maintenance_status"=>"0" }
          trigger.merge! host
          #trigger.merge! trigger.delete("items").last
          bestItem = ''
          itemIndex = 100000
          trigger["items"].each do |item|
            index = 0
            index = trigger["expression"].index(item["key_"])
            if index.to_i < itemIndex then
              itemIndex = index
              bestItem = item
            end
          end
          trigger.merge! bestItem if bestItem.is_a? Hash
          trigger.merge! trigger.delete("lastEvent") if trigger["lastEvent"].is_a?(Hash)
          if trigger["maintenance_status"] == "1"
            trigger["status"] = :mnt
          elsif trigger["acknowledged"] == "1"
            trigger["status"] = :ack
          else
            trigger["status"] = :una
          end
          trigger["priority"] = trigger["priority"].to_i
          trigger["value_type"] = trigger["value_type"].to_i
          trigger
        end
        # Add known last_ack info from ald triggers
        if @triggers && !@triggers.empty? && !args[:full]
          old_triggers = @triggers.dup
          triggers.reverse_each do |trigger|
            old_tirger = nil
            while !old_triggers.empty? && trigger.fetch("lastchange") >= old_triggers.last.fetch("lastchange")
              if old_triggers.last["triggerid"] == trigger["triggerid"]
                old_tirger = old_triggers.pop
                trigger.merge! old_tirger.merge trigger
                break
              else
                old_triggers.pop
              end
            end
          end
        end
        @triggers = triggers
      else
        @triggers = []
      end
      @timestamp = Time.now
    end

    def get_last_ack_message!
      connect_to_zabbix
      ack_triggers_events = []
      LOG.debug { "[last_ack] overall triggers count: #{@triggers.count}" }
      LOG.debug { "[last_ack] without ack message: #{@triggers.reject{ |t| t["message"] }.count}" }
      @triggers.reject{ |t| t["message"] }.each do |trigger|
        if trigger["status"] == :ack
          ack_triggers_events << trigger["eventid"]
        else
          event =  @@zbx.events_by_object(trigger["triggerid"])
          begin
            trigger.merge!(event.select{ |e| not e["acknowledges"].empty?}.first["acknowledges"].first || {}) unless event.empty?
          rescue
            LOG.debug "[app] Failed to get last ack message from #{event}"
          end
        end
      end
      events = @@zbx.events(ack_triggers_events)
      events.each do |event|
        @triggers.select{ |trigger| trigger["eventid"] == event["eventid"] }.first.merge!(event["acknowledges"].first || {})
      end
    end

    def add_from_mail(triggers = [])
      triggers = [triggers] if triggers.is_a? String
      return unless triggers.respond_to?(:each)
      triggers.each do |trigger|
        priority, host, description = trigger.split(' ', 3)
        next unless priority && host && description
        description.chomp!(" PROBLEM")
        description.chomp!(" OK")
        @triggers <<  { "priority" => PRIORITY_NC.index(priority),
                        "host" => host,
                        "description" => description,
                      }
      end
    end

    def each
      @triggers.each { |trigger| yield trigger }
      @triggers
    end

    alias map each

    def to_a
      @triggers
    end

    def ids
      @triggers.map{ |trigger| trigger["triggerid"] }.compact
    end

    def event_ids
      @triggers.map{ |trigger| trigger["eventid"] }.compact
    end

    def hosts
      @triggers.map{ |trigger| trigger["host"] }.uniq.compact
    end

    ["una", "ack", "mnt"].each do |status|
      self.class_eval %Q(
      def #{status}
        self.class.new @triggers.select { |trigger| trigger["status"] == :#{status} }
      end
      )
    end

    alias unacknowledged una
    alias acknowledged ack
    alias maintenance mnt

    def filter_priority(priority = (1..MAX_PRIORITY))
      priority = case priority
      when Range
        priority
      when Integer
        Range.new(priority, MAX_PRIORITY)
      when /^(\d+)$/
        Range.new($1.to_i, MAX_PRIORITY)
      when /(^\d+)\.\.(\d+)$/
        Range.new($1.to_i, $2.to_i)
      when /^=(\d+)$/
        Range.new($1.to_i, $1.to_i)
      when /^~(\d+)$/
        Range.new($1.to_i, MAX_PRIORITY)
      else
        Range.new(options[:priority].to_i, MAX_PRIORITY)
      end
      self unless priority.is_a? Range
      priority ? self.class.new(@triggers.select { |trigger| trigger["priority"] && priority.include?(trigger["priority"]) }) : self
    end

    def filter_status(list = nil)
      (list && !list.empty?) ? self.class.new(@triggers.select { |trigger| trigger["status"] && list.include?(trigger["status"]) }) : self
    end

    ["description", "host", "message"].each do |filter_name|
      self.class_eval %Q(
      def filter_#{filter_name}(expr, rev = false)
        return self unless expr
        action = rev ? :reject : :select
        pattern = Regexp.new(expr, Regexp::IGNORECASE)
        LOG.debug "[filter] #{filter_name} filter pattern: \#{pattern}"
        self.class.new(@triggers.public_send(action) { |trigger| trigger["#{filter_name}"] && trigger["#{filter_name}"].match(pattern) })
      end
      )
    end

    def set_acknowledge!(message = nil)
      return unless message
      return if event_ids.empty?
      connect_to_zabbix
      @@zbx.acknowledge event_ids, message
    end

    def reacknowledge!
      connect_to_zabbix
      @triggers.each { |trigger| @@zbx.acknowledge trigger["eventid"], trigger["message"] }
    end

    def count
      @triggers.count
    end

    alias size count

    def [](index)
      @triggers[index]
    end

    def first
      @triggers.first
    end

    def last
      @triggers.last
    end

    def empty?
      @triggers.empty?
    end

    def to_table()
      LOG.debug "[viewer] entry count: #{@triggers.count}"
      table_entries = []
      long_strings = []
      with_last_ack = @triggers.reduce(nil) { |memo, t| memo || t["message"] }
      @triggers.each.with_index(1) do |t, index|
        values = []
        values << index
        values << (PRIORITY[t["priority"]] rescue "N/A")
        values << get_short_hostname(t["host"])
        values << (t["description"].is_a?(String) ? t["description"].split(" ").map{ |x| x.split('.').uniq.join('.') }.join(' ') : "n/a")
        begin
          values << Float(t["lastvalue"]).to_s[0..11]
        rescue
          if !t["lastvalue"]
            values << "n/a"
          elsif t["lastvalue"].size < 13
            values << t["lastvalue"].split($/).join(' ')
          else
            values << "*"
            long_strings << "*#{index}: #{t["lastvalue"]}"
          end
        end
        values << (t["lastchange"] ? time_to_age(t["lastchange"]) : "n/a")
        values << (STATUS[t["status"]] rescue "n/a")
        if with_last_ack
          if t["message"]
            message = t["message"].chomp.chomp("----[BULK ACKNOWLEDGE]----").chomp(" [BULK ACK zab api]")
            (message.size / 50).times.with_index do |ind|
              message.insert((ind + 1) * 50 + ind, $/)
            end
            values << message.chomp
          else
            values << ''
          end
          values << t["alias"]
        end
        table_entries << values
      end
      headings = %w(no prior host issue value age st)
      headings += %w(last_ack who) if with_last_ack
      require "terminal-table"
      table = table_entries.empty? ? '' : Terminal::Table.new(:headings => headings, :rows => table_entries).to_s
      $stdout.tty? ? (table + $/ + long_strings.map{ |string| string.chomp }.join($/)) : table
    end

    def to_compact
      table_entries = []
      @triggers.each.with_index(1) do |t, index|
        values = []
        values << (PRIORITY_COMPACT[t["priority"]] rescue "U")
        values << get_short_hostname(t["host"])[0..20]
        values << (t["description"].is_a?(String) ? t["description"].split.map{ |x| x.split('.').uniq.join('.') }.join(' ')[0..45] : "n/a")
        begin
          values << Float(t["lastvalue"]).to_s[0..11]
        rescue
          if !t["lastvalue"]
            values << "n/a"
          elsif t["lastvalue"].size < 13
            values << t["lastvalue"].split($/).join(' ')
          else
            values << "*"
            #long_strings << "*#{index}: #{t["lastvalue"]}"
          end
        end
        values << (t["lastchange"] ? time_to_age(t["lastchange"]) : "n/a")
        table_entries << values
      end
      LOG.debug table_entries.inspect
      headings = %w(p host issue value age)
      require "terminal-table"
      table = table_entries.empty? ? '' : Terminal::Table.new(
        :headings => headings,
        :rows => table_entries,
        :style => {:padding_left => 0, :padding_right => 0}
      ).to_s
      #$stdout.tty? ? (table + $/ + long_strings.map{ |string| string.chomp }.join($/)) : table
      table
    end

    def to_mail
      @triggers.reduce('') { |str, t| str << "#{PRIORITY_NC[t["priority"]]} #{t["host"]} #{t["description"]} PROBLEM" << $/ }
    end

    def to_json
      require 'oj'
      @triggers.reduce('') { |str, t| str << Oj.dump(t) << $/ }
    end

    def to_jira_desc
      table_entries = []
      long_strings = []
      @triggers.each.with_index(1) do |t, index|
        values = []
        values << index
        values << "[#{get_short_hostname t["host"]}|#{@jira_url}/issues/?jql=text%20~%20#{t["host"]}%20OR%20text%20~%20#{t["host"].split('.').first}%20ORDER%20BY%20updated%20DESC]"
        values << (t["url"] && !t["url"].empty? ? "[#{t["description"]}|#{t["url"]}]" : t["description"])
        if t["lastvalue"]
          begin
            values << Float(t["lastvalue"])
          rescue
            if t["lastvalue"].size < 21
              values << t["lastvalue"].split($/).join(' ')
            else
              values << "*"
              long_strings << "{noformat}*#{index}: #{t["lastvalue"]}{noformat}"
            end
          end
          if t["value_type"] == 0 or t["value_type"] == 3 then
              values[-1] = "[#{values[-1]}|#{@zabbix_url}/history.php?itemid=#{t["itemid"]}&action=showgraph]"
          else
            values[-1] = "[#{values[-1]}|#{@zabbix_url}/history.php?itemid=#{t["itemid"]}&action=showvalues]"
          end
        else
          values << "n/a"
        end
        table_entries << values
      end
      headings = %w(no host issue value)
      require "terminal-table"
      table = table_entries.empty? ? '' : Terminal::Table.new(:headings => headings, :rows => table_entries)
      table = table.to_s.split($/).reject{ |x| x =~ /^[+-]+$/ }.join($/)
      table + $/ + long_strings.join($/)
    end

    alias to_jira to_jira_desc

    def to_hosts
      hosts.join($/)
    end

    def time_to_age(time)
      age = [60, 60, 24, 30].reduce([Time.now.to_i - time.to_i]) do |memo, divider|
        x = memo.pop
        memo.push x % divider
        memo.push x / divider
      end.reverse
      ind = age.index { |x| x != 0 }
      ind -= 1 if ind == (age.size - 1)
      sprintf "%02d%s %02d%s", *age.zip(%w(m d h m s))[ind..ind+1].flatten
    end

    def get_short_hostname(name)
      name = name.to_s
      return name if name.include? 'vpn.'
      name =~ /(\d{1,3}\.){3}\d{1,3}/ ? name : name.split('.').first
    rescue
      name
    end

  end
end
