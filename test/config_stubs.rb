# frozen_string_literal: true

module ConfigStubs
  extend ActiveSupport::Concern

  class ConfigStub
    def initialize(**opts)
      @config = ActiveSupport::OrderedOptions.new.
                update({ adapter: :test }.merge(**opts))
    end

    def config_for(_file)
      @config
    end

    def executor
      @executor ||= ExectorStub.new
    end

    class ExectorStub
      def run!
      end
    end
  end

  def with_cable_config(**opts)
    Rails.stub(:application, ConfigStub.new(**opts)) { yield }
  end
end
