# frozen_string_literal: true

class CreateChannels < ActiveRecord::Migration[7.2]
  def change
    create_table "solid_cable_channels", force: :cascade do |t|
      t.integer "channel_hash", limit: 8, null: false
      t.integer "subscribers", default: 0, null: false
      t.datetime "created_at", null: false
      t.index ["channel_hash"], name: "index_solid_cable_channels_on_channel_hash"
    end
  end
end
