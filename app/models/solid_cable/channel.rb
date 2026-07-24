# frozen_string_literal: true

module SolidCable
  class Channel < SolidCable::Record
    class << self
      def for(channel)
        find_or_initialize_by(id: ::SolidCable::Message.channel_hash_for(channel))
      end
    end
  end
end
