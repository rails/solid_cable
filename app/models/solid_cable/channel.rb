# frozen_string_literal: true

module SolidCable
  class Channel < SolidCable::Record
    scope :for, ->(channel) { where(channel_hash: channel_hash_for(channel)) }

    def increment_subscribers!
      update!(subscribers: subscribers + 1)
    end

    def decrement_subscribers!
      update!(subscribers: [ subscribers - 1, 0 ].max)
    end
  end
end
