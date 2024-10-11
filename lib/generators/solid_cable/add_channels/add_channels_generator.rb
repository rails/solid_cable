# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

class SolidCable::AddChannelsGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  def copy_files
    migration_template "db/migrate/create_channels.rb",
                       "db/cable_migrate/create_channels.rb"
  end
end
