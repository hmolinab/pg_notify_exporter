## Installation
### Debian instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --ingroup prometheus
 $ sudo apt install git ruby ruby-dev libpq-dev build-essential patch ruby-bundler -y
 ```
### Red Hat/Centos 8 instructions
```
 $ grep -qs prometheus /etc/group || sudo groupadd prometheus
 $ id prometheus || sudo /usr/sbin/adduser prometheus --system --no-create-home --shell /sbin/nologin --gid prometheus
 $ sudo dnf install git ruby ruby-devel postgresql-devel gcc make redhat-rpm-config glibc-headers openssl-devel rubygem-bundler rubygem-openssl -y
 ```
### General instructions
```
$ sudo mkdir -p /opt/prometheus/exporters
$ sudo chown $(whoami) /opt/prometheus/exporters
$ cd /opt/prometheus/exporters
$ git clone --depth 1 https://github.com/hmolinab/pg_notify_exporter.git
$ cd pg_notify_exporter
$ $(which bundle) install 
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
### Red Hat/Centos 7 instructions
You must provided a ruby version gratter or equal than 2.5 (ie: softwarecollections.org, rvm, etc). The file bin/pg_notify_exporter can help you to start the service.
