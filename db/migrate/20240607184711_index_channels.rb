# frozen_string_literal: true

class IndexChannels < ActiveRecord::Migration[7.1]
  def change
    add_index :solid_cable_messages, :channel, length: 500
  end
end
