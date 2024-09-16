require "test_helper"
require_relative "../../../../../lib/generators/solid_cable/install/install_generator"

class SolidCable::InstallGeneratorTest < Rails::Generators::TestCase
  tests SolidCable::InstallGenerator
  destination File.expand_path("../../../../../tmp", __dir__)

  setup :prepare_destination
  setup :run_generator

  test "cable_schema exists" do
    assert_file "db/cable_schema.rb"
  end

  test "cable.yml exists" do
    assert_file "config/cable.yml"
  end
end
