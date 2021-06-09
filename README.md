# pg_notify_export
## PostgreSQL Listen/Notify exporter for Prometheus
Do you need business metrics to get insights with Prometheus?
pg_notify_expoter uses the PostgreSQL feature Listen/Notify to export to Prometheus events triggered in table operations (INSERT, UPDATE and DELETE).

This tool is useful to monitoring data behaviour from Prometheus without touch the application code. You must be careful about the labels guidelines  https://prometheus.io/docs/practices/naming/.

In general you'll be able to count events (INSERT, UPDATE or DELETE) for specific table. I started using pg_notify_expoter to detect 90 minutes without transactions for a specific supplier.

pg_notify_expoter can create for you triggers at the tables, also you can customize the trigger up to you and finally you are going to get a metric as follow:
```
# TYPE postgres_notify counter
# HELP postgres_notify Events counter:
pg_notify{operation="INSERT",host="db1.example.org",database="traffic",tag="carrier_one",schema="tx",table="outbund"} 1999994.0
```

With only one pg_notify_export Installation you can get metrics from many machines and many tables without touch your business logic.

pg_notify_export is able to reconnect when the database connection is lost but it wont monitoring a database if the database is down when it is starting. Also, at this time only receives events from triggers, you can test to send "notify" as a queue, this is not supported at this time.

The following is trigger's function defined by config/trigger_functions.yml and it's performed when the perform_setup is enable:

```
---
- name: simple_event_notification
  function_body: |
    CREATE OR REPLACE FUNCTION simple_event_notification()
        RETURNS trigger AS $$
      DECLARE
        record RECORD;
        payload JSON;
        err_context text;
      BEGIN
        IF (TG_OP = 'DELETE') THEN
          record = OLD;
        ELSE
          record = NEW;
        END IF;

        payload = json_build_object('table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
                                    'action', TG_OP,
                                    'data', json_build_object(NULL),
                                    'timestamp',now()::text);

        PERFORM pg_notify('pg_notify_exporter', payload::text);
        RETURN NEW;
      EXCEPTION
        WHEN others THEN
            GET STACKED DIAGNOSTICS err_context = PG_EXCEPTION_CONTEXT;
            RAISE INFO 'Error Name:%',SQLERRM;
            RAISE INFO 'Error State:%', SQLSTATE;
            RAISE INFO 'Error Context:%', err_context;
            RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
...

```

pg_notify_exporter waits for a JSON stream as payload, you can adapt this portion of code:
```
SELECT code into label_code FROM data.master WHERE id=NEW.id;

payload = json_build_object('table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
                            'action', TG_OP,
                            'data', json_build_object('code',label_code),
                            'timestamp',now()::text);
```



## Installation
### Debian instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --ingroup prometheus
 $ sudo usermod -aG sudo prometheus # don't panic, we are going to be remediate it
 $ sudo apt install git ruby ruby-dev libpq-dev build-essential patch -y
 ```
### Red Hat/Centos 8 instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --gid prometheus
 $ sudo usermod -aG wheel prometheus
 $ sudo dnf install git ruby ruby-devel postgresql-devel gcc make redhat-rpm-config glibc-headers -y
 ```
### General instructions
```
$ sudo gem install bundler
$ sudo mkdir -p /opt/prometheus/exporters
$ sudo chown prometheus /opt/prometheus/ -R
$ cd /opt/prometheus/exporters
$ sudo /sbin/runuser -u prometheus -- git clone --depth 1 https://github.com/hmolinab/pg_notify_exporter.git
$ cd pg_notify_exporter
$ sudo runuser -u prometheus -- $(which bundle) install
$ sudo usermod -G prometheus prometheus
$ sudo runuser -u prometheus cp config/events_config.yml.disable config/events_config.yml
$ [ -d log ] || sudo runuser -u prometheus mkdir log
$ [ -d var ] || sudo runuser -u prometheus mkdir var
$ sudo chmod +x bin/pg_notify_exporter
$ sudo  cp /opt/prometheus/exporters/pg_notify_exporter/systemd/pg_notify_exporter.service /lib/systemd/system/
$ sudo systemctl daemon-reload
$ sudo systemd-analyze verify pg_notify_exporter.service
$ # Warning: please edit your config, it needs a valid database
$ sudo systemctl enable --now pg_notify_exporter
$ curl http://localhost:9292/metrics
```
### Red Hat/Centos 7 instructions
You must provided a ruby version gratter or equal than 2.5 (ie: softwarecollections.org, rvm, etc). It requires to fix the bin/pg_notify_exporter file.

## Configuration
The config/events_config.yml file must be configured by adding the tables to be monitored and indicating their events.
```
---
  - localhost:
    - database: test
      tag: b2b_localhost
      perform_setup: true
      username: monitor_user
      password: secret
      enabled:  yes
      monitors:
      - table: logistica.order
        enabled: yes
        columns_to_label:
          - id:
            - 1
            - 2
            - 3
        events:
          - insert
      - table: one
        enabled: yes
        events:
          - INSERT
          - delete
```
* monitors: YAML array to configure the listener by table
* table: name of the table to which events will be created to listen for notifications
* enable: enabled true/false
* events: list of events in the table that will be notified (insert, update, delete)
## Execution
If you test by hand, or your are setting the trigger function the ruckup statement that will enable the service on port 9292 must be executed:
```
 # puma -b tcp://0.0.0.0.0:9292
 Puma starting in single mode...
* Version 4.3.6 (ruby 2.6.5-p114), codename: Mysterious Traveller
* Min threads: 0, max threads: 16
* Environment: development
* Listening on tcp://127.0.0.0.1:9292
* Listening on tcp://[::1]:9292
Use Ctrl-C to stop
```
For production the better way to use the systemd integration disabling the perform_setup configuration and using a monitor username.
```
systemctl start pg_notify_exporter
```

## Operation
When starting the service it reads the details provided in the configuration file connecting to each database, then it creates the event_on_table_notify function and finally it creates a trigger for each table defined in the defined events.

If you want to delete the triggers, simply disable the database, which causes the triggers to be deleted. it is also possible to disable a particular table.

For the trigger creation, the database and the tables must be enabled. It is important to point out that if a database is disabled, the application will still try to connect,
to prevent the connection it must be commented in the configuration.

## Dropping functions
If you want to drop the functions the configuration is as following:
```
perform_setup: true
enabled:  false
```
