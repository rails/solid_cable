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
      cable_config.silence_polling != false
    end

    def polling_interval
      parse_duration(cable_config.polling_interval, default: 0.1.seconds)
    end

    def message_retention
      parse_duration(cable_config.message_retention, default: 1.day)
    end

    def autotrim?
      cable_config.autotrim != false
    end

    def trim_batch_size
      if (size = cable_config.trim_batch_size.to_i) < 2
        100
      else
        size
      end
    end

    def use_skip_locked
      cable_config.use_skip_locked != false
    end

    # For every write that we do, we attempt to delete trim_chance times as
    # many records. This ensures there is downward pressure on the cache size
    # while there is valid data to delete. Read this as 'every time the trim job
    # runs theres a trim_multiplier chance this trims'. Adjust number to make it
    # more or less likely to trim. Only works like this if trim_batch_size is
    # 100
    def trim_chance
      2
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
