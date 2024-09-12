# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

class SolidCable::UpdateGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  def copy_files
    migration_template "db/migrate/create_compact_channel.rb",
                       "db/cable_migrate/create_compact_channel.rb"
  end
end
