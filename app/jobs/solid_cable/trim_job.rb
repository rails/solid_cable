# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform
      return unless trim?

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

      def trim?
        expires_per_write = (1 / trim_batch_size.to_f) * ::SolidCable.trim_chance

        rand < (expires_per_write - expires_per_write.floor)
      end
  end
end
