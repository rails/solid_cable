# frozen_string_literal: true

require "solid_cable/version"
require "solid_cable/engine"
require "action_cable/subscription_adapter/solid_cable"

module SolidCable
  mattr_accessor :connects_to

  def self.silence_polling?
    !!Rails.application.config_for("cable")[:silence_polling]
  end

  def self.polling_interval
    Rails.application.config_for("cable")[:polling_interval].presence || 0.1
  end

  def self.keep_messages_around_for
    duration = Rails.application.config_for("cable")[:keep_messages_around_for]

    if duration.present?
      amount, units = duration.to_s.split(".")
      amount.to_i.public_send(units)
    else
      30.minutes
    end
  end
end
