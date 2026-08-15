# frozen_string_literal: true

module SolidCable
  class Engine < ::Rails::Engine
    isolate_namespace SolidCable

    config.after_initialize do
      if SolidCable.encrypt? && Record.lease_connection.adapter_name == "PostgreSQL" && Rails::VERSION::MAJOR == 7
        raise \
          "Cannot enable encryption for Solid Cable: in Rails 7, Active Record Encryption does not support " \
          "encrypting binary columns on PostgreSQL"
      end
    end
  end
end
