# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :trimmable, lambda {
      where(created_at: ...::SolidCable.message_retention.ago)
    }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel_hash: channel_hashes_for(channels)).
        where(id: (last_id + 1)..).order(:id)
    }

    class << self
      def broadcast(channel, payload)
        channel_hash = channel_hash_for(channel)
        insert({ created_at: Time.current, channel:, payload:, channel_hash: })

        ::SolidCable::Channel.find_by(channel_hash:)&.subscribers.to_i
      end
    end
  end
end
