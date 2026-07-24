class CreateSolidCableChannels < ActiveRecord::Migration[8.2]
  def change
    create_table :solid_cable_channels, id: false do |t|
      t.bigint :id, null: false, primary_key: true
      t.bigint :current_id, null: false, default: 0
    end

    add_column :solid_cable_messages, :channel_id, :bigint, if_not_exists: true
    add_index :solid_cable_messages, [ :channel_hash, :channel_id ], unique: true
  end
end
