# frozen_string_literal: true

# This migration comes from active_error (originally 20200727225318)
class CreateActiveErrorInstances < ActiveRecord::Migration[7.1]
  def change
    create_table :active_error_instances do |t|
      t.belongs_to :fault
      t.text :url
      t.binary :headers, limit: 512.megabytes
      t.binary :parameters, limit: 512.megabytes

      t.timestamps
    end
  end
end
