# frozen_string_literal: true

require "test_helper"
require "config_stubs"

class SolidCableTest < ActiveSupport::TestCase
  include ConfigStubs

  test "it has a version number" do
    assert SolidCable::VERSION
  end

  test "autotrimming when nothing is set" do
    assert_not Rails.application.config_for("cable").key?(:autotrim)
    assert SolidCable.autotrim?
  end

  test "autotrimming when set to false" do
    with_cable_config autotrim: false do
      assert_not SolidCable.autotrim?
    end
  end

  test "autotrimming when set to true" do
    with_cable_config autotrim: true do
      assert SolidCable.autotrim?
    end
  end

  test "default trim_batch_size is 100" do
    assert_equal 100, SolidCable.trim_batch_size
  end

  test "trim_batch_size when set badly" do
    with_cable_config trim_batch_size: "weird" do
      assert_equal 100, SolidCable.trim_batch_size
    end
  end

  test "trim_batch_size when set" do
    with_cable_config trim_batch_size: 42 do
      assert_equal 42, SolidCable.trim_batch_size
    end
  end
end
