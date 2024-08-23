# frozen_string_literal: true

# This migration comes from solid_cable (originally 20240103034713)
class CreateSolidCableMessage < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_cable_messages, if_not_exists: true do |t|
      t.text :channel
      t.text :payload

      t.timestamps

      t.index :created_at
    end
  end
end
