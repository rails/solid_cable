# frozen_string_literal: true

module SolidCable
  class Message
    module Encryption
      extend ActiveSupport::Concern

      included do
        if SolidCable.encrypt?
          encrypts :payload, **SolidCable.encryption_context_properties, support_unencrypted_data: true
        end
      end
    end
  end
end
