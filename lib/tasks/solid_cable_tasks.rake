# frozen_string_literal: true

desc "Copy over the schema and set cable adapter for Solid Cable"
namespace :solid_cable do
  task :install do
    Rails::Command.invoke :generate, [ "solid_cable:install" ]
  end

  task :update do
    Rails::Command.invoke :generate, [ "solid_cable:update" ]
  end
end
