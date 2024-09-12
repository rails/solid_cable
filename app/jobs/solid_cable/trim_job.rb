# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform
      trim_batches.times do
        ::SolidCable::Message.transaction do
          ids = ::SolidCable::Message.trimmable.non_blocking_lock.
                limit(trim_batch_size).pluck(:id)
          ::SolidCable::Message.where(id: ids).delete_all
        end
      end
    end

    private

    def trim_batch_size
      ::SolidCable.trim_batch_size
    end

    def trim_batches
      expires_per_write =
        (1 / trim_batch_size.to_f) * ::SolidCable.trim_chance
      batches = expires_per_write.floor
      overflow_batch_chance = expires_per_write - batches
      batches += 1 if rand < overflow_batch_chance
      batches
    end
  end
end
