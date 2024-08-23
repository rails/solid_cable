# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
load "rails/tasks/engine.rake"
load "rails/tasks/statistics.rake"
require "rake/testtask"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task default: :test
