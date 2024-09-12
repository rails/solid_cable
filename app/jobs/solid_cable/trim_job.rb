# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform(id = nil)
      id ||= ::SolidCable::Message.maximum(:id)

      return unless (id % (trim_batch_size / 2)).zero?

      ::SolidCable::Message.transaction do
        ids = ::SolidCable::Message.trimmable.non_blocking_lock.
              limit(trim_batch_size).pluck(:id)
        ::SolidCable::Message.where(id: ids).delete_all
      end
    end

    private

    def trim_batch_size
      ::SolidCable.trim_batch_size
    end
  end
end
