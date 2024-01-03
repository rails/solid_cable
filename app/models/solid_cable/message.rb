# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :prunable, -> { where(created_at: ..30.minutes.ago) }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel: channels).where(id: (last_id + 1)..).order(:id)
    }

    def prune
      prunable.delete_all
    end
  end
end
