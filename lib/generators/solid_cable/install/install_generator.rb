# frozen_string_literal: true

class SolidCable::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  def copy_files
    template "db/cable_schema.rb"
    template "config/cable.yml", force: true
  end
end
