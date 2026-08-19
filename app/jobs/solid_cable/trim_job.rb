# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform(trim_batch_size: ::SolidCable.trim_batch_size)
      ::SolidCable::Message.transaction do
        ids = ::SolidCable::Message.trimmable.non_blocking_lock.
              limit(trim_batch_size).pluck(:id)
        ::SolidCable::Message.where(id: ids).delete_all
      end
    end
  end
end
