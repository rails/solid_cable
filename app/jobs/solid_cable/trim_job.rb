# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform(id = ::SolidCable::Message.maximum(:id))
      return unless (id % (trim_batch_size / 2)).zero?

      ::SolidCable::Message.trimmable.
        limit(trim_batch_size).non_blocking_lock.delete_all
    end

    private

    def trim_batch_size
      ::SolidCable.trim_batch_size
    end
  end
end
