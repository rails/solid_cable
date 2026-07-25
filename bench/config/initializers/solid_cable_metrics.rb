# frozen_string_literal: true

require "json"

  module SolidCableBenchmarkMetrics
    REPORT_INTERVAL = ENV.fetch("SOLID_CABLE_METRICS_INTERVAL", "5").to_f

    class << self
      def record(measurements)
        snapshot = synchronize do
          measurements.each do |name, values|
            observed_values = Array(values).compact
            samples[name].concat(observed_values) if observed_values.any?
          end

          next unless monotonic_time - @last_report_at >= REPORT_INTERVAL

          @last_report_at = monotonic_time
          samples_to_report = @samples
          @samples = new_samples
          samples_to_report
        end

        report(snapshot) if snapshot
      end

      private
        def samples
          @samples ||= new_samples
        end

        def new_samples
          Hash.new { |hash, key| hash[key] = [] }
        end

        def synchronize(&block)
          mutex.synchronize(&block)
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def report(snapshot)
          metrics = snapshot.transform_values { |values| summarize(values) }
          return if metrics.empty?

          message = JSON.generate(
            event: "solid_cable_metrics",
            pid: Process.pid,
            metrics:
          )

          Rails.logger.log_at(Logger::INFO) { Rails.logger.info(message) }
        end

        def summarize(values)
          sorted = values.sort

          {
            count: sorted.size,
            average: round(sorted.sum.fdiv(sorted.size)),
            p50: round(percentile(sorted, 0.50)),
            p95: round(percentile(sorted, 0.95)),
            max: round(sorted.last)
          }
        end

        def percentile(sorted, percentile)
          sorted.fetch((percentile * sorted.size).ceil - 1)
        end

        def round(value)
          value.round(3)
        end
    end

    @last_report_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

ActiveSupport::Notifications.monotonic_subscribe(/\.solid_cable\z/) do |name, started_at, finished_at, _, payload|
  duration_ms = (finished_at - started_at) * 1_000
  measurements =
    case name
    when "broadcast.solid_cable"
      { insert_ms: duration_ms }
    when "subscription_cursor.solid_cable"
      { subscription_cursor_ms: duration_ms }
    when "poll.solid_cable"
      pool = payload[:pool] || {}

      {
        poll_ms: duration_ms,
        poll_interval_ms: payload[:interval_ms],
        poll_rows: payload[:rows],
        poll_lag_ms: payload[:lags_ms],
        pool_busy: pool[:busy],
        pool_idle: pool[:idle],
        pool_waiting: pool[:waiting],
        pool_connections: pool[:connections]
      }
    when "callback.solid_cable"
      {
        executor_queue_ms: payload[:queue_ms],
        callback_ms: duration_ms
      }
    else
      {}
    end

  SolidCableBenchmarkMetrics.record(measurements)
end
