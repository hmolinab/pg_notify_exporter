require 'observer'
require 'json'
require 'yaml'

RECONNECT_TIMEOUT = 10
CHANNEL = 'pg_notify_exporter'

class Metrics
  include Observable

  def initialize(worker, log)
    @log    = log
    @worker = worker
    @worker.add_observer(self)
    @config = @worker.config
    #@log.info(self)
  end

  def reconnected_database(host,db,connection)
    database_iteration(host,db,true,connection)
  end


  def create_listener(host,db,connection)
    Thread.new do

      @log.info "Adding listener #{CHANNEL.to_sym} at #{db['database']}@#{host}"
      detail = ''
     begin
        channel=CHANNEL.to_sym
        connection.listen(channel, loop: true) do |_channel, _pid, payload|
          register = {}
          valid_data = false
          detail = JSON.parse(payload)
          db['monitors'].each do |monitor|
            next if monitor['columns_to_label'].nil?
            monitor['columns_to_label'].each do |column_to_label|
              key = column_to_label.keys.first
              unless detail['data'][key].nil?
                next unless column_to_label[key].include?(detail['data'][key])
                valid_data = true
                register.store(key.to_sym,detail['data'][key])
              end
            end

          end
          register.store(:operation, detail['action'])
          register.store(:host, host)
          register.store(:database, db['database'])
          register.store(:tag, db['tag'])
          register.store(:table, detail['table'])
          if valid_data
            @log.info "Message registered: #{db['database']}@#{host} ~ #{detail}"
            @event_trigger.increment(labels: register)
          else
            @log.info "Message discarded : #{db['database']}@#{host} ~ #{detail}"
          end
        end
      rescue
        changed
        connection.disconnect
        @log.error "Last message:"
        @log.error detail
        @log.error "Recovering connection #{db['database']}@#{host}"
        notify_observers(host,db,self)
      end #begin
    end #thread
  end

  # Counters initialization
  def prometheus_registry_event(host,database,tag,monitor)
    register = {}
    @labels.each {|label| register.store(label,nil)}
    register.store(:host,host)
    register.store(:database,database)
    register.store(:tag,tag)

    # Set the initial values for all counters
    monitor['events'].each do |event|
      event.upcase!
      register.store(:operation,event)
      register.store(:table,monitor['table'])

      # counter: columns_to_label
      unless monitor['columns_to_label'].nil?
        monitor['columns_to_label'].each do |column_to_label|
          column_to_label.each do |column, values|
            values.each do |value|
              value.upcase! if value.class == String
              register.store(column.to_sym,value)
              @event_trigger.increment(by: 0, labels: register)
            end
          end
        end
      else
        @event_trigger.increment(by: 0, labels: register)
        @log.info "Registering event: postgres://#{database}@#{host}/#{monitor['table']}"
      end

    end #monitor
  end

  def database_iteration(host,db,reconnecting=false,connection=nil)
    # Perform database actions
    id_db = db['database']+'@'+host
    if db['enabled']
      unless connection.nil?
        @dbs[id_db] = connection
      else
        @dbs[id_db] = @worker.database_setup(host,db)
      end
    else
      @worker.database_unsetup(host,db)
      return
    end

    # Create channel listener
    create_listener(host,db,@dbs[id_db])

    # Start exporters
    db['monitors'].each do |monitor|
      unless reconnecting
        self.prometheus_registry_event(host,db['database'],db['tag'],monitor)
      end
    end
  end

  def prometheus_create_counters
    @labels = [:operation, :host, :tag, :database, :table]
    @config.each do |entry|
      entry.each do |host,databases|
        databases.each do |db|
          db['monitors'].each do |monitor|
            # adding label: columns_to_label
            unless monitor['columns_to_label'].nil?
              monitor['columns_to_label'].each do |column_to_label|
                column_to_label.each do |column, values|
                  key = column.downcase.to_sym
                  @labels.push(key) unless @labels.include?(key)
                end # column_to_label
              end # monitors['columns_to_label']
            end # unless monitor[columns_to_label]
          end # db['monitors']
        end #databases
      end # entry
    end # @config
    prometheus = Prometheus::Client.registry
    @event_trigger = prometheus.counter(CHANNEL.to_sym,
                  docstring: 'Events counter: ',
                  labels: @labels)
  end

  def start
    prometheus_create_counters

    @dbs = {}
    @config.each do |entry|
      entry.each do |host,databases|
        databases.each do |db|
          database_iteration(host,db)
        end #databases
      end # entry
    end # @config
  end

end
