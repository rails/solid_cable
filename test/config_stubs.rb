# frozen_string_literal: true

module ConfigStubs
  extend ActiveSupport::Concern

  class ConfigStub
    def initialize(**)
      @config = ActiveSupport::OrderedOptions.new.
                update({ adapter: :test }.merge(**))
    end

    def config_for(_file)
      @config
    end
  end

  def with_cable_config(**)
    Rails.stub(:application, ConfigStub.new(**)) { yield }
  end
end
