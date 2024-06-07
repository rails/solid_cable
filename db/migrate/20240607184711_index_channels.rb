class IndexChannels < ActiveRecord::Migration[7.1]
  def change
    add_index :solid_cable_messages, :channel
  end
end
