# frozen_string_literal: true

require "solid_cable/version"
require "solid_cable/engine"
require "solid_cable/configuration"
require "solid_cable/batched_broadcaster"
require "action_cable/subscription_adapter/solid_cable"

module SolidCable
  class << self
    delegate :connects_to, :silence_polling?, :polling_interval,
      :message_retention, :autotrim?, :trim_batch_size, :use_skip_locked,
      :trim_chance, :reconnect_attempts, :writer_batch_size, :writer_batch_delay,
      :encrypt?, :encryption_context_properties,
      to: :configuration

    def configuration
      @configuration ||= Configuration.new(**Rails.application.config_for("cable"))
    end

    def configure(**options)
      @configuration = Configuration.new(**options)
    end

    def reset_configuration!
      @configuration = nil
    end
  end
end
