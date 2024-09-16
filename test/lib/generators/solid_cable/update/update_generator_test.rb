require "test_helper"
require_relative "../../../../../lib/generators/solid_cable/update/update_generator"

class SolidCable::UpdateGeneratorTest < Rails::Generators::TestCase
  tests SolidCable::UpdateGenerator
  destination File.expand_path("../../../../../tmp", __dir__)

  setup :prepare_destination
  setup :run_generator

  test "cable_schema exists" do
    assert_migration "db/cable_migrate/create_compact_channel.rb"
  end
end
