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

  test "encryption is disabled by default" do
    configuration = SolidCable::Configuration.new

    assert_not configuration.encrypt?
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

  test "duration settings keep valid ruby-style values" do
    configuration = SolidCable::Configuration.new(
      message_retention: "1.day",
      polling_interval: "0.1.seconds",
      writer_batch_delay: "0.001.seconds"
    )

    assert_equal 1.day, configuration.message_retention
    assert_equal 0.1.seconds, configuration.polling_interval
    assert_equal 0.001.seconds, configuration.writer_batch_delay
  end

  test "duration settings accept a duration or a number of seconds" do
    configuration = SolidCable::Configuration.new(
      message_retention: 2.hours,
      polling_interval: 0.5,
      writer_batch_delay: 30
    )

    assert_equal 2.hours, configuration.message_retention
    assert_equal 0.5.seconds, configuration.polling_interval
    assert_equal 30.seconds, configuration.writer_batch_delay
    assert_equal 86400.seconds, SolidCable::Configuration.new(message_retention: 86400).message_retention
  end

  test "invalid duration settings fall back to their defaults" do
    configuration = SolidCable::Configuration.new(
      message_retention: "1 day",
      polling_interval: "1",
      writer_batch_delay: "soon"
    )

    assert_equal 1.day, configuration.message_retention
    assert_equal 0.1.seconds, configuration.polling_interval
    assert_equal 0.001.seconds, configuration.writer_batch_delay

    missing = SolidCable::Configuration.new
    assert_equal 1.day, missing.message_retention
    assert_equal 0.1.seconds, missing.polling_interval
    assert_equal 0.001.seconds, missing.writer_batch_delay
  end
end
