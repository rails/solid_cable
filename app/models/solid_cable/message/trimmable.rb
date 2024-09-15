# frozen_string_literal: true

module SolidCable
  module Message::Trimmable
    extend ActiveSupport::Concern

    included do
      scope :trimmable, lambda {
        where(created_at: ..::SolidCable.message_retention.ago)
      }
    end
  end
end
