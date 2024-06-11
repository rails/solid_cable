# frozen_string_literal: true

require "solid_cable/version"
require "solid_cable/engine"
require "action_cable/subscription_adapter/solid_cable"

module SolidCable
  class << self
    def connects_to
      cable_config.connects_to.to_h.deep_transform_values(&:to_sym)
    end

    def silence_polling?
      !!cable_config.silence_polling
    end

    def polling_interval
      parse_duration(cable_config.polling_interval, default: 0.1.seconds)
    end

    def keep_messages_around_for
      parse_duration(cable_config.keep_messages_around_for, default: 1.day)
    end

    private

    def cable_config
      Rails.application.config_for("cable")
    end

    def parse_duration(duration, default:)
      if duration.present?
        *amount, units = duration.to_s.split(".")
        amount.join(".").to_f.public_send(units)
      else
        default
      end
    end
  end
end
