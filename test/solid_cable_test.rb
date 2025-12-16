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

    with_cable_config trim_batch_size: "0" do
      assert_equal 100, SolidCable.trim_batch_size
    end
  end

  test "trim_batch_size when set" do
    with_cable_config trim_batch_size: 42 do
      assert_equal 42, SolidCable.trim_batch_size
    end
  end

  test "reconnect_attempts defaults to a single zero" do
    assert_equal [ 0 ], SolidCable.reconnect_attempts
  end

  test "reconnect_attempts accepts an integer" do
    with_cable_config reconnect_attempts: 3 do
      assert_equal [ 0, 0, 0 ], SolidCable.reconnect_attempts
    end
  end

  test "reconnect_attempts accepts an array" do
    with_cable_config reconnect_attempts: [ 0, 1, 2 ] do
      assert_equal [ 0, 1, 2 ], SolidCable.reconnect_attempts
    end
  end
end
