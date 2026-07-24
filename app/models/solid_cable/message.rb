# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :trimmable, lambda {
      where(created_at: ...::SolidCable.message_retention.ago)
    }
    scope :broadcastable, lambda { |cursors|
      cursors.group_by { |_, channel_id| channel_id }.
        reduce(none) do |messages, (channel_id, channels)|
          channel_hashes = channels.map(&:first)

          messages.or(where(channel_hash: channel_hashes, channel_id: (channel_id + 1)..))
        end.
        order(:channel_hash, :channel_id)
    }

    class << self
      def broadcast(channel, payload)
        broadcast_batch([[channel, payload]])
      end

      def broadcast_batch(messages)
        created_at = Time.current

        insert_all!(
          messages.map do |channel, payload|
            {
              channel: channel,
              payload: payload,
              channel_hash: channel_hash_for(channel),
              created_at: created_at
            }
          end
        )
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
