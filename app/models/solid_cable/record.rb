# frozen_string_literal: true

module SolidCable
  class Record < ActiveRecord::Base
    self.abstract_class = true

    connects_to(**SolidCable.connects_to) if SolidCable.connects_to.present?

    def self.non_blocking_lock
      if SolidCable.use_skip_locked
        lock(Arel.sql("FOR UPDATE SKIP LOCKED"))
      else
        lock
      end
    end
  end
end
