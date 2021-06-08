# config.ru

require 'rack'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'
require 'prometheus/client'
require 'sequel'
require 'logger'
require_relative 'app/metrics'
require_relative 'app/worker'

use Rack::Deflater
use Prometheus::Middleware::Collector
use Prometheus::Middleware::Exporter


log     = Logger.new('log/run.log',shift_age='daily')
worker  = Worker.new(log)
metrics = Metrics.new(worker,log)
run metrics.start
