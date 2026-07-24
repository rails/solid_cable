ActiveRecord::Schema[7.1].define(version: 1) do
  create_table "solid_cable_channels", id: false, force: :cascade do |t|
    t.bigint "id", null: false, primary_key: true
    t.bigint "current_id", default: 0, null: false
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.binary "payload", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "channel_hash", limit: 8, null: false
    t.bigint "channel_id", null: false
    t.index [ "channel_hash", "channel_id" ], name: "index_solid_cable_messages_on_channel_hash_and_channel_id", unique: true
    t.index [ "channel_hash" ], name: "index_solid_cable_messages_on_channel_hash"
    t.index [ "created_at" ], name: "index_solid_cable_messages_on_created_at"
  end
end
