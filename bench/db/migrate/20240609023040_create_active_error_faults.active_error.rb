# frozen_string_literal: true

# This migration comes from active_error (originally 20200727220359)
class CreateActiveErrorFaults < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize
    create_table :active_error_faults do |t|
      t.belongs_to :cause
      t.binary :backtrace, limit: 512.megabytes
      t.binary :backtrace_locations, limit: 512.megabytes
      t.string :klass
      t.text :message
      t.string :controller
      t.string :action
      t.integer :instances_count
      t.text :blamed_files, limit: 512.megabytes
      t.text :options

      t.timestamps
    end
  end
end
