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

## Configuration
The config/events_config.yml file must be configured by adding the tables to be monitored and indicating their events.
```
---
---
  - localhost:
    - database: test
      tag: business_tag
      perform_setup: true
      username: postgres
      password: secret
      enabled:  true
      monitors:
      - table: one
        enabled: yes
        function: notification_with_payload
        columns_to_label:
          - code:
            - 'alpha'
            - 'beta'
            - 'gamma'
        events:
          - insert
      - table: two
        enabled: yes
        function: simple_event_notification
        events:
          - INSERT
          - delete
        #columns_to_label:
        #  - id:
        #    - 1
...
```
### configuration keys


| Config key | Value | Mandatory |
|------------|-------|:---------:|
| localhost | Database host | yes |
| database  | Database name | yes |
| tag | Business tag | yes |
| perform_setup | true or false | yes |
| username | Connection username | yes |
| password | Connection password | yes |
| enabled  | true or false | yes |
| monitors | Config section | yes |
| table | table name | yes |
| enabled  | true or false | yes |
| function | Function name | yes |
| columns_to_label | Config section | yes |
| code |  Config section | no |
| events | insert, delete, update | yes |


## Execution
### Testing
If you test by hand, or your are setting the trigger function the ruckup statement that will enable the service on port 9292 must be executed:
```
 $ bundle install
 $ bundle exec puma -C config/puma.rb --dir .
 Puma starting in single mode...
```
### Test tables
```
CREATE TABLE public.one (
    code character varying
);



CREATE TABLE public.two (
    id integer
);
```
Play time:
```
insert into one values('ALPHA');
```
and
```
$ curl http://localhost:9292/metrics | grep pg_notify_exporter
```

### Production
For production the better way is to use the systemd integration, disabling the perform_setup configuration and using a non privileged username. See systemd/README.md.

## Operation
When starting the service it reads the details provided in the configuration file connecting to each database, then it creates the defined function and finally it creates a trigger for each defined table.

For the trigger creation, the database and the tables must be enabled. It is important to point out that if a database is disabled, the application will still try to connect,
to prevent the connection it must be commented in the configuration.

## Dropping functions
If you want to drop the functions the configuration is as following:
```
perform_setup: true
enabled:  false
```
