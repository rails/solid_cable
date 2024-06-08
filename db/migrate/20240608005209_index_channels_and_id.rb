class IndexChannelsAndId < ActiveRecord::Migration[7.1]
  def change
    add_index :solid_cable_messages, %i(channel id), length: 500
  end
end
