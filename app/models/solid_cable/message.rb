# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :trimmable, lambda {
      where(created_at: ...::SolidCable.message_retention.ago)
    }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel_hash: channel_hashes_for(channels)).
        where(id: (last_id.to_i + 1)..).order(:id)
    }

    class << self
      def broadcast(channel, payload)
        insert({ created_at: Time.current, channel:, payload:,
          channel_hash: channel_hash_for(channel) })
      end

      def channel_hashes_for(channels)
        channels.map { |channel| channel_hash_for(channel) }
      end

      # Need to unpack this as a signed integer since Postgresql and SQLite
      # don't support unsigned integers
      def channel_hash_for(channel)
        Digest::SHA256.digest(channel.to_s).unpack1("q>")
      end
    end
  end
end
