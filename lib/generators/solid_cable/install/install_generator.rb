# frozen_string_literal: true

class SolidCable::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  class_option :database,
               type: :string, aliases: %i(--db),
               desc: "The database for your migration. By default, the " \
                     "current environment's primary database is used."
  class_option :skip_migrations, type: :boolean, default: nil,
                                 desc: "Skip migrations"

  def create_migrations
    return if options[:skip_migrations]

    db_clause = "DATABASE=#{options[:database]}" if options[:database].present?

    rails_command "railties:install:migrations FROM=solid_cable #{db_clause}".strip,
                  inline: true
  end
end
