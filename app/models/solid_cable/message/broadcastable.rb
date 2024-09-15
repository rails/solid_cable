# frozen_string_literal: true

module SolidCable
  module Message::Broadcastable
    extend ActiveSupport::Concern

    included do
      scope :broadcastable, lambda { |channels, last_id|
        where(channel_hash: channel_hashes_for(channels)).
          where(id: (last_id + 1)..).order(:id)
      }
    end

    class_methods do
      def broadcast(channel, payload)
        insert({ channel:, payload:, channel_hash: channel_hash_for(channel) })
      end
    end
  end
end
