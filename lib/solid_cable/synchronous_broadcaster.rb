# frozen_string_literal: true

require "concurrent"

module SolidCable
  class SynchronousBroadcaster
    include Trimming

    Stopped = BatchedBroadcaster::Stopped

    def initialize
      @mutex = Mutex.new
      @stopped = false
      @background = Concurrent::FixedThreadPool.new(1, max_queue: 100, fallback_policy: :discard)
    end

    def broadcast(channel, payload)
      @mutex.synchronize do
        raise Stopped, "Solid Cable writer has stopped" if @stopped

        Rails.application.executor.wrap do
          result = SolidCable::Message.broadcast(channel, payload)
          track_successful_write if SolidCable.autotrim?
          result
        end
      end
    end

    def shutdown
      @mutex.synchronize do
        @stopped = true
        @background.shutdown
      end
      @background.wait_for_termination
    end

    private
      def track_successful_write
        track_writes(1)
      rescue StandardError => error
        Rails.error.report(error)
      end

      def async(&block)
        @background << -> do
          Rails.application.executor.wrap(&block)
        rescue Exception => error # rubocop:disable Lint/RescueException
          Rails.error.report(error)
        end
      end
  end
end
