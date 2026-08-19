# frozen_string_literal: true

require "concurrent"

module SolidCable
  class BatchedBroadcaster
    include Trimming

    Stopped = Class.new(StandardError)
    Message = Struct.new(:channel, :payload, keyword_init: true)

    def initialize(batch_size: SolidCable.writer_batch_size, batch_delay: SolidCable.writer_batch_delay)
      @batch_size = batch_size
      @batch_delay = batch_delay
      @queue = Queue.new
      @background = Concurrent::FixedThreadPool.new(1, max_queue: 100, fallback_policy: :discard)

      @thread = Thread.new do
        Thread.current.name = "solid_cable_writer"
        Thread.current.abort_on_exception = true
        listen_for_initial_messages
      end
    end

    def broadcast(channel, payload)
      message = Message.new(channel:, payload:)

      queue.enq message
    rescue ClosedQueueError
      raise Stopped, "Solid Cable writer has stopped"
    end

    def shutdown
      queue.close
      thread.join
      background.shutdown
      background.wait_for_termination
    end

    private
      attr_reader :batch_size, :batch_delay, :queue, :thread, :background

      def listen_for_initial_messages
        loop do
          message = queue.pop

          break if message.nil?

          collect_batch(message)
        end
      end

      def collect_batch(first_message)
        batch = [ first_message ]
        deadline = monotonic_time + batch_delay

        drain_queue_into(batch)
        wait_for_messages_until(batch, deadline)

        flush(batch)
      end

      def drain_queue_into(batch)
        while batch.size < batch_size && (message = queue.pop(timeout: 0))
          batch << message
        end
      end

      def wait_for_messages_until(batch, deadline)
        while batch.size < batch_size && (remaining = deadline - monotonic_time).positive?
          message = queue.pop(timeout: remaining)
          break if message.nil?

          batch << message
        end
      end

      def flush(batch)
        Rails.application.executor.wrap do
          SolidCable::Message.
            broadcast_batch(batch.map { |message| [ message.channel, message.payload ] })
          track_writes(batch.size) if SolidCable.autotrim?
        end
      rescue StandardError => error
        Rails.error.report(error)
      end

      def async(&block)
        background << -> do
          Rails.application.executor.wrap(&block)
        rescue Exception => error # rubocop:disable Lint/RescueException
          Rails.error.report(error)
        end
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
