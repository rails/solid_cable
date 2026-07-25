# frozen_string_literal: true

require "json"

module SolidCableBenchmarkMetrics
  REPORT_INTERVAL = ENV.fetch("SOLID_CABLE_METRICS_INTERVAL", "5").to_f

  class << self
    def record(measurements)
      unless mutex.try_lock
        @dropped_metric_records = @dropped_metric_records.to_i + 1
        return
      end

      report_data =
        begin
          reset_after_fork

          measurements.each do |name, values|
            record_samples(name, values)
          end

          now = monotonic_time
          if now - @last_report_at >= REPORT_INTERVAL
            elapsed = now - @last_report_at
            @last_report_at = now
            samples_to_report = @samples
            @samples = new_samples

            [ samples_to_report, process_metrics(elapsed) ]
          end
        ensure
          mutex.unlock
        end

      report(*report_data) if report_data
    end

    private
      def samples
        @samples ||= new_samples
      end

      def new_samples
        Hash.new { |hash, key| hash[key] = [] }
      end

      def record_samples(name, values)
        if values.is_a?(Array)
          values.each { |value| samples[name] << value if value }
        elsif values
          samples[name] << values
        end
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def process_cpu_time
        Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      end

      def reset_after_fork
        return if @pid == Process.pid

        @pid = Process.pid
        @last_report_at = monotonic_time
        @last_process_cpu_at = process_cpu_time
        @last_gc_stat = GC.stat
        @samples = new_samples
        @dropped_metric_records = 0
      end

      def process_metrics(elapsed)
        cpu_at = process_cpu_time
        gc_stat = GC.stat

        metrics = {
          cpu_ms: round((cpu_at - @last_process_cpu_at) * 1_000),
          cpu_percent: round((cpu_at - @last_process_cpu_at).fdiv(elapsed) * 100),
          allocated_objects: gc_stat[:total_allocated_objects] - @last_gc_stat[:total_allocated_objects],
          allocations_per_second: round(
            (gc_stat[:total_allocated_objects] - @last_gc_stat[:total_allocated_objects]).fdiv(elapsed)
          ),
          minor_gc_count: gc_stat[:minor_gc_count] - @last_gc_stat[:minor_gc_count],
          major_gc_count: gc_stat[:major_gc_count] - @last_gc_stat[:major_gc_count],
          gc_time_ms: gc_stat[:time] - @last_gc_stat[:time],
          heap_live_slots: gc_stat[:heap_live_slots],
          heap_free_slots: gc_stat[:heap_free_slots],
          old_objects: gc_stat[:old_objects],
          threads: Thread.list.count,
          dropped_metric_records: @dropped_metric_records.to_i
        }

        @last_process_cpu_at = cpu_at
        @last_gc_stat = gc_stat
        @dropped_metric_records = 0
        metrics
      end

      def report(snapshot, process)
        metrics = snapshot.transform_values { |values| summarize(values) }
        return if metrics.empty?

        message = JSON.generate(
          event: "solid_cable_metrics",
          pid: Process.pid,
          process:,
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

ActiveSupport::Notifications.monotonic_subscribe("perform_action.action_cable") do |_, started_at, finished_at, _, payload|
  next unless payload[:action] == :ping

  SolidCableBenchmarkMetrics.record(
    action_ms: (finished_at - started_at) * 1_000
  )
end

ActiveSupport::Notifications.monotonic_subscribe("broadcast.action_cable") do |_, started_at, finished_at, _, _|
  SolidCableBenchmarkMetrics.record(
    action_cable_broadcast_ms: (finished_at - started_at) * 1_000
  )
end

ActiveSupport::Notifications.monotonic_subscribe("transmit.action_cable") do |_, started_at, finished_at, _, _|
  SolidCableBenchmarkMetrics.record(
    transmit_ms: (finished_at - started_at) * 1_000
  )
end

ActiveSupport::Notifications.monotonic_subscribe("command.benchmark_action_cable") do |_, started_at, finished_at, _, payload|
  duration_ms = (finished_at - started_at) * 1_000
  measurements =
    case payload[:command]
    when :message
      {
        inbound_action_queue_ms: payload[:queue_ms],
        action_command_ms: duration_ms
      }
    when :subscribe
      {
        inbound_subscription_queue_ms: payload[:queue_ms],
        subscription_command_ms: duration_ms
      }
    else
      {
        inbound_other_queue_ms: payload[:queue_ms],
        other_command_ms: duration_ms
      }
    end

  SolidCableBenchmarkMetrics.record(measurements)
end

module ActionCableBenchmarkWorkerMetrics
  def async_invoke(receiver, method, *args, connection: receiver, &block)
    queued_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    command = benchmark_command_type(method, args)

    executor.post do
      ActiveSupport::Notifications.instrument(
        "command.benchmark_action_cable",
        queue_ms: benchmark_milliseconds_since(queued_at),
        command:
      ) do
        invoke(receiver, method, *args, connection:, &block)
      end
    end
  end

  private
    def benchmark_command_type(method, args)
      return :other unless method == :dispatch_websocket_message

      case args.first
      when /"command"\s*:\s*"message"/
        :message
      when /"command"\s*:\s*"subscribe"/
        :subscribe
      else
        :other
      end
    end

    def benchmark_milliseconds_since(started_at)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
    end
end

ActionCable::Server::Worker.prepend(ActionCableBenchmarkWorkerMetrics)
