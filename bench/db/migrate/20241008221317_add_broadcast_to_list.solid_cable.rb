# frozen_string_literal: true

class AddBroadcastToList < ActiveRecord::Migration[7.2]
  def change
    add_column :solid_cable_messages, :broadcast_to_list, :boolean, null: false, default: false
  end
end
