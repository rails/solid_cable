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

  test "reconnect_attempts accepts unlimited from YAML or Ruby" do
    [ "unlimited", :unlimited ].each do |attempts|
      with_cable_config reconnect_attempts: attempts do
        assert_equal :unlimited, SolidCable.reconnect_attempts
      end
    end
  end

  test "unlimited reconnection interval defaults to five seconds" do
    assert_equal 5, SolidCable::Configuration.new.reconnect_interval
  end

  test "unlimited reconnection interval is configurable" do
    with_cable_config reconnect_interval: "0.5.seconds" do
      assert_equal 0.5, SolidCable.reconnect_interval
    end
  end

  test "unlimited reconnection interval must be positive and finite" do
    [ "0.seconds", "-1.second", "1e309.seconds" ].each do |interval|
      with_cable_config reconnect_interval: interval do
        assert_raises(ArgumentError) { SolidCable.reconnect_interval }
      end
    end
  end

  test "encryption is disabled by default" do
    configuration = SolidCable::Configuration.new

    assert_not configuration.encrypt?
  end

  test "inline broadcasts are disabled by default" do
    assert_not SolidCable::Configuration.new.inline_broadcasts?
  end

  test "inline broadcasts can be enabled and disabled" do
    with_cable_config inline_broadcasts: true do
      assert SolidCable.inline_broadcasts?
      SolidCable.configuration.inline_broadcasts = false
      assert_not SolidCable.inline_broadcasts?
    end

    with_cable_config inline_broadcasts: false do
      assert_not SolidCable.inline_broadcasts?
    end
  end

  test "encryption is enabled when configured" do
    configuration = SolidCable::Configuration.new(encrypt: true)

    assert configuration.encrypt?
    properties = configuration.encryption_context_properties
    assert_instance_of ActiveRecord::Encryption::MessagePackMessageSerializer,
      properties[:message_serializer]
  end

  test "custom encryption context properties" do
    encryptor = ActiveRecord::Encryption::Encryptor.new
    configuration = SolidCable::Configuration.new(
      encrypt: true,
      encryption_context_properties: { "encryptor" => encryptor }
    )

    assert_same encryptor, configuration.encryption_context_properties[:encryptor]
  end
end
