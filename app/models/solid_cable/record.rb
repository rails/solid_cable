# frozen_string_literal: true

module SolidCable
  class Record < ActiveRecord::Base
    self.abstract_class = true

    connects_to(**SolidCable.connects_to) if SolidCable.connects_to
  end
end
