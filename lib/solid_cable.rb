require "solid_cable/version"
require "solid_cable/engine"
require "action_cable/subscription_adapter/solid_cable"

module SolidCable
  mattr_accessor :connects_to

  def self.silence_polling?
    !!Rails.application.config_for("cable")[:silence_polling]
  end
end
