# frozen_string_literal: true

module SolidCable
  module Retrying
    private
      # Waits the delay for this attempt (counting from 1) and returns true,
      # or returns false once there is no delay left for it.
      def retry_attempt?(attempt, delays)
        return false if attempt > delays.size

        delay = delays[attempt - 1]
        sleep(delay) if delay > 0

        true
      end
  end
end
