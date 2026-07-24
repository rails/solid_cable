# frozen_string_literal: true

module SolidCable
  class Channel < SolidCable::Record
    def self.for(channel)
      create_or_find_by(id: ::SolidCable::Message.channel_hash_for(channel))
    end
  end
end
