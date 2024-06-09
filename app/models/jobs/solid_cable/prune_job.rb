# frozen_string_literal: true

module SolidCable
  class PruneJob < ActiveJob::Base
    def perform
      ::SolidCable::Message.prunable.delete_all
    end
  end
end
