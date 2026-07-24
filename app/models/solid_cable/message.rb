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
        broadcast_batch([ [ channel, payload ] ])
      end

      def broadcast_batch(messages)
        messages_by_channel = messages.group_by { |channel, _| channel_hash_for(channel) }
        channel_ids = messages_by_channel.keys.sort

        ::SolidCable::Channel.transaction do
          ::SolidCable::Channel.insert_all(channel_ids.map { |id| { id: id } })

          channels = ::SolidCable::Channel.where(id: channel_ids).order(:id).lock.index_by(&:id)

          created_at = Time.current
          attributes = channel_ids.flat_map do |channel_id|
            channel = channels.fetch(channel_id)
            channel_messages = messages_by_channel.fetch(channel_id)
            first_id = channel.current_id + 1

            channel_messages.each_with_index.map do |(channel_name, payload), index|
              {
                channel: channel_name,
                payload: payload,
                channel_hash: channel_id,
                channel_id: first_id + index,
                created_at: created_at
              }
            end
          end

          current_ids = Arel::Nodes::Case.new(::SolidCable::Channel.arel_table[:id])
          channel_ids.each do |channel_id|
            channel = channels.fetch(channel_id)
            increment = messages_by_channel.fetch(channel_id).size
            current_ids.when(channel_id).then(channel.current_id + increment)
          end

          ::SolidCable::Channel.where(id: channel_ids).update_all(current_id: current_ids)
          insert_all!(attributes)
        end
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
