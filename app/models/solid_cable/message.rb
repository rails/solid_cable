# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    has_one :channel_record, class_name: "::SolidCable::Channel",
      foreign_key: :channel_hash, primary_key: :channel_hash

    scope :trimmable, lambda {
      where(created_at: ...::SolidCable.message_retention.ago)
    }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel_hash: channel_hashes_for(channels)).
        where(id: (last_id + 1)..).order(:id)
    }

    class << self
      def broadcast(channel, payload)
        insert({ created_at: Time.current, channel:, payload:,
          channel_hash: channel_hash_for(channel) })

        channel_record&.subscribers.to_i
      end
    end
  end
end
