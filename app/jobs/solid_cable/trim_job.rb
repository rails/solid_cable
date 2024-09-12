# frozen_string_literal: true

module SolidCable
  class TrimJob < ActiveJob::Base
    def perform
      ::SolidCable::Message.trimmable.delete_all
    end
  end
end
