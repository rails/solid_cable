# frozen_string_literal: true

class RemoveChannelIndex < ActiveRecord::Migration[7.2]
  def up
    remove_index :solid_cable_messages, :channel, if_exists: true
  end

  def down
    add_index :solid_cable_messages, :channel, if_not_exists: true
  end
end
