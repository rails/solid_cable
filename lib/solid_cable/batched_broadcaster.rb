# frozen_string_literal: true

module SolidCable
  class BatchedBroadcaster
    Stopped = Class.new(StandardError)
    Message = Struct.new(:channel, :payload, :enqueued_at, keyword_init: true)

    def initialize(queue_size: SolidCable.writer_queue_size, batch_size: SolidCable.writer_batch_size, batch_delay: SolidCable.writer_batch_delay)
      @batch_size = batch_size
      @batch_delay = batch_delay
      @queue = SizedQueue.new(queue_size)

      @thread = Thread.new do
        Thread.current.name = "solid_cable_writer"
        Thread.current.abort_on_exception = true
        listen_for_initial_messages
      end
    end

    def broadcast(channel, payload)
      message = Message.new(channel:, payload:, enqueued_at: monotonic_time)

      queue.enq message
    rescue ClosedQueueError
      raise Stopped, "Solid Cable writer has stopped"
    end

    def shutdown
      queue.close
      thread.join
    end

    private
      attr_reader :batch_size, :batch_delay, :queue, :thread

      def listen_for_initial_messages
        loop do
          message = queue.pop

          break if message.nil?

          collect_batch(message)
        end
      end

      def collect_batch(first_message)
        batch = [ first_message ]
        deadline = first_message.enqueued_at + batch_delay

        while batch.size < batch_size && (remaining = deadline - monotonic_time).positive?
          message = queue.pop(timeout: remaining)
          break if message.nil?

          batch << message
        end

        flush(batch)
      end

      def flush(batch)
        Rails.application.executor.wrap do
          SolidCable::Message.
            broadcast_batch(batch.map { |message| [ message.channel, message.payload ] })
        end
      rescue StandardError => error
        Rails.error.report(error)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
