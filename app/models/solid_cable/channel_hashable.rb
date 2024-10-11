# frozen_string_literal: true

module SolidCable::ChannelHashable
  extend ActiveSupport::Concern

  class_methods do
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
