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
            if monitor['tags'].nil?
              valid_data = true
              register.store(:tag, '')
              next
            end

            monitor['tags'].each do |tag|
              valid_data = true if tag == detail['tag']
              register.store(:tag, detail['tag'])
            end
          end
          register.store(:operation, detail['action'])
          register.store(:host, host)
          register.store(:database, db['database'])
          register.store(:table, detail['table'])
          if valid_data 
            @log.info "Message registered: #{db['database']}@#{host} ~ #{detail}"
            @event_trigger.increment(labels: register)
          else
            @log.info "Message discarted : #{db['database']}@#{host} ~ #{detail}"
          end
        end
      rescue
        changed
        #connection.disconnect
        @log.error $!
        @log.error "Last message:"
        @log.error detail
        @log.error "Recovering connection #{db['database']}@#{host}"
        notify_observers(host,db,self)
      end #begin
    end #thread
  end

  # Counters initialization
  def prometheus_registry_event(host,database,monitor)
    register = {}
    @labels.each {|label| register.store(label,nil)}
    register.store(:host,host)
    register.store(:database,database)
    #register.store(:tag,tag)

    # Set the initial values for all counters
    monitor['events'].each do |event|
      event.upcase!
      register.store(:operation,event)
      register.store(:table,monitor['table'])
      @event_trigger.increment(by: 0, labels: register)
    end 

    unless monitor['tags'].nil?
      monitor['tags'].each do |tag|
        register.store(:tag,tag)
        @event_trigger.increment(by: 0, labels: register)
      end
    end

    @log.info "Registering event: postgres://#{database}@#{host}/#{monitor['table']}"
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
        self.prometheus_registry_event(host,db['database'],monitor)
      end
    end
  end

  def prometheus_create_counters
    @labels = [:operation, :host, :tag, :database, :table]
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
