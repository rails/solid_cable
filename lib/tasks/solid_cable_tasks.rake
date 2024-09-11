# frozen_string_literal: true

desc "Copy over the schema and set cache for Solid Cable"
namespace :solid_cable do
  task :install do
    Rails::Command.invoke :generate, ["solid_cable:install"]
  end
end
