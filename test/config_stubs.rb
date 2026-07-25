# frozen_string_literal: true

module ConfigStubs
  extend ActiveSupport::Concern

  def with_cable_config(**)
    SolidCable.configure(**)
    yield
    SolidCable.reset_configuration!
  end
end
