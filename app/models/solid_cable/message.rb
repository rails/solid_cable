# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :prunable, lambda {
      where(created_at: ..::SolidCable.keep_messages_around_for.ago)
    }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel: channels).where(id: (last_id + 1)..).order(:id)
    }

    def self.prune
      prunable.delete_all
    end
  end
end
