# frozen_string_literal: true

module ConfigStubs
  extend ActiveSupport::Concern

  def with_cable_config(**options)
    SolidCable.configure(**Rails.application.config_for("cable").to_h.deep_symbolize_keys, **options)
    yield
    SolidCable.reset_configuration!
  end
end
