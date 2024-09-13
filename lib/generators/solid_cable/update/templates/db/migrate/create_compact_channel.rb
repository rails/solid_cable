# frozen_string_literal: true

class CreateCompactChannel < ActiveRecord::Migration[7.2]
  def change
    change_column :solid_cable_messages, :channel, :binary, limit: 1024, null: false
    add_column :solid_cable_messages, :channel_hash, :integer, limit: 8, if_not_exists: true
    add_index :solid_cable_messages, :channel_hash, if_not_exists: true
    change_column :solid_cable_messages, :payload, :binary, limit: 536_870_912, null: false

    SolidCable::Message.find_each do |msg|
      msg.update(channel_hash: SolidCable::Message.channel_hash_for(msg.channel))
    end
  end
end
