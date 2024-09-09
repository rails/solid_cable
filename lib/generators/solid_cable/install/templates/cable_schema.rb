# frozen_string_literal: true

ActiveRecord::Schema[7.1].define(version: 1) do
  create_table "solid_cable_messages", force: :cascade do |t|
    t.text "channel"
    t.text "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel",
                         length: 500
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end
end
