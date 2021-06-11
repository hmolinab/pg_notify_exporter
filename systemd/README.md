## Installation
### Debian instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --ingroup prometheus
 $ sudo apt install -y ruby ruby-bundler
 $ sudo apt install -y git ruby-dev libpq-dev build-essential patch
 ```
### Red Hat/Centos 8 instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --gid prometheus
 $ sudo dnf install -y ruby rubygem-bundler rubygem-openssl
 $ sudo dnf install -y git ruby-devel postgresql-devel gcc make redhat-rpm-config glibc-headers openssl-devel
 ```
### General instructions
```
$ sudo mkdir -p /opt/prometheus/exporters
$ sudo chown $(whoami) /opt/prometheus/exporters
$ cd /opt/prometheus/exporters
$ git clone --depth 1 https://github.com/hmolinab/pg_notify_exporter.git
$ cd pg_notify_exporter
$ sudo $(which bundle) install
$ cp config/events_config.yml.disable config/events_config.yml
$ mkdir -p log var
$ PUMA_BIN=$(which puma)
$ sed -i -e "s#PUMA_BIN#$PUMA_BIN#g" systemd/pg_notify_exporter.service
$ sudo chown prometheus.prometheus /opt/prometheus/ -R
$ sudo cp /opt/prometheus/exporters/pg_notify_exporter/systemd/pg_notify_exporter.service /lib/systemd/system/
$ sudo systemd-analyze verify pg_notify_exporter.service
$ sudo systemctl daemon-reload
$ # Warning: edit your config, it needs a valid database
$ sudo systemctl enable --now pg_notify_exporter
$ curl http://localhost:9292/metrics
```
*Warnings:*
1. `prometheus` user doesn't have home and it generates some troubles with the bundle Installation, that is why the procedure executes `bundle install` with `sudo`. You can considerer to create the `prometheus` with home.
1. You can consider cleanning up the develop packages.

### Red Hat/Centos 7 instructions
You must provided a ruby version gratter or equal than 2.5 (ie: softwarecollections.org, rvm, etc). The file bin/pg_notify_exporter can help you to start the service.
