# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2024_10_08_221317) do
  create_table "active_error_faults", force: :cascade do |t|
    t.integer "cause_id"
    t.binary "backtrace", limit: 536870912
    t.binary "backtrace_locations", limit: 536870912
    t.string "klass"
    t.text "message"
    t.string "controller"
    t.string "action"
    t.integer "instances_count"
    t.text "blamed_files", limit: 536870912
    t.text "options"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cause_id"], name: "index_active_error_faults_on_cause_id"
  end

  create_table "active_error_instances", force: :cascade do |t|
    t.integer "fault_id"
    t.text "url"
    t.binary "headers", limit: 536870912
    t.binary "parameters", limit: 536870912
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fault_id"], name: "index_active_error_instances_on_fault_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.binary "payload", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "channel_hash", limit: 8, null: false
    t.boolean "broadcast_to_list", default: false, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end
end
