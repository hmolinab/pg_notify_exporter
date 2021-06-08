

class Worker
  attr_reader :config

  def initialize(log)
    config    = File.dirname(File.expand_path(__FILE__)) + '/../config/events_config.yml'
    functions = File.dirname(File.expand_path(__FILE__)) + '/../config/trigger_functions.yml'
    @log      = log
    @config   = YAML::load(File.open(config))
    @functions= YAML::load(File.open(functions))
    @log.info "Reading configuration:"
    @log.info @config
    #@log.info @functions
    @reconecting_list = Hash.new
  end

  def add_observer(metrics)
    metrics.add_observer(self)
  end

  def update(host,db,boss)
    reconect_database(host,db,boss)
  end

  def reconect_database(host,db,boss)
    # Validating if there is a reconnecting thread
    if @reconecting_list[host+db['database']].nil?
      @reconecting_list[host+db['database']] = true
    elsif @reconecting_list[host+db['database']] == true
      return
    end

    Thread.new do
      connection = nil
      loop do
        @log.info "Reconnecting #{host}-#{db['database']}"
        connection = nil
        connection = database_setup(host,db)
        break if connection
        sleep RECONNECT_TIMEOUT
      end
      @reconecting_list[host+db['database']] = false
      boss.reconnected_database(host,db,connection)
    end
  end

  def build_trigger(monitor)
    events = ''
    monitor['events'].each do |event|
      events += event + ' OR '
    end
    events = events[0..events.size-5]
    trigger_statement =<<~EOS
    CREATE TRIGGER trigger_#{monitor['function']}
      AFTER #{events} ON #{monitor['table']}
      FOR EACH ROW
      EXECUTE PROCEDURE #{monitor['function']}()
    EOS
    return trigger_statement
  end

  def database_connect(host,db)
    target = "postgres://#{host}/#{db['database']}"
    conn_str   = "host=#{host} "
    conn_str  += "dbname=#{db['database']} "
    conn_str  += "user=#{db['username']} "
    conn_str  += "password=#{db['password']} "
    #conn_str  += "gssencmode=disable"
    begin
      @log.info "Connecting: #{target}"
      connection = Sequel.postgres(conn_str: conn_str + " password=#{db['password']} ")
    rescue
      @log.error "It's not possible to connect: #{conn_str}"
      #@log.error $!
      return false
    end
    @log.info connection.inspect
    return connection
  end

  def get_funtion(monitor)
    @functions.each do |function|
      next unless function['name'] == monitor['function']
      return function['function_body']
    end
    @log.error "No function #{monitor['function']} found."
  end

  def database_setup(host,db)

    connection = database_connect(host,db)
    @log.info "Connection: #{connection.inspect}"
    if connection == false
      return false
    end

    # Returns if the setup is not needed
    return connection unless db['perform_setup']


    db['monitors'].each do |monitor|

      # Basic Table name Validating
      next if monitor['table'].nil?

      # Drop triggers
      drop_triggers = "DROP TRIGGER IF EXISTS trigger_#{monitor['function']} on #{monitor['table']}"
      connection.run drop_triggers
      @log.info "#{db['database']}@#{host} Trigger dropped at: #{monitor['table']}"

      # Jump if either database or table is disabled
      # This is to clean triggers
      unless monitor['enabled'] && db['enabled']
        log.info "Bypassing by configuration #{monitor['table']}"
        next
      end

      # NOTIFY_FUNCTION creation
      function_statement = get_funtion(monitor)
      connection.run function_statement
      @log.info "Adding functions"
      @log.info "#{db['database']}@#{host} Function created: #{monitor['function']}"

      # Trigger creation
      trigger_statement = build_trigger(monitor)
      connection.run trigger_statement
      @log.info "Adding triggers"
      @log.info trigger_statement.gsub("\n",' ')

    end #db['monitors']
    return connection

    return true
  end

  def database_unsetup(host,db)
    return unless db['perform_setup']
    connection = database_connect(host,db)
    db['monitors'].each do |monitor|
      @log.info "db['database']}@#{host} Dropping function: function:#{monitor['function']}"
      connection.run "DROP FUNCTION if EXISTS #{monitor['function']} CASCADE" if db['perform_setup']
    end
    connection.disconnect
  end

end
