# frozen_string_literal: true

module SolidCable
  module Trimming
    # For every write that we do, we attempt to delete TRIM_MULTIPLIER times as
    # many records. This ensures there is downward pressure on the message count
    # while there is old data to delete.
    TRIM_MULTIPLIER = 2

    private
      def track_writes(count)
        trim_batches(count).times { async { TrimJob.perform_now } }
      end

      def trim_batches(count)
        trims_per_write = (1 / SolidCable.trim_batch_size.to_f) * TRIM_MULTIPLIER
        batches = (count * trims_per_write).floor
        overflow_batch_chance = count * trims_per_write - batches
        batches += 1 if rand < overflow_batch_chance
        batches
      end
  end
end
