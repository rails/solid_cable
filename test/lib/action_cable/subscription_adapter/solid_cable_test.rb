# frozen_string_literal: true

require "test_helper"
require "concurrent"

require "active_support/core_ext/hash/indifferent_access"
require "pathname"
require "config_stubs"

class ActionCable::SubscriptionAdapter::SolidCableTest < ActionCable::TestCase
  include ConfigStubs

  WAIT_WHEN_EXPECTING_EVENT = 1
  WAIT_WHEN_NOT_EXPECTING_EVENT = 0.2

  setup do
    server = ActionCable::Server::Base.new
    server.config.cable = cable_config.with_indifferent_access
    server.config.logger = Logger.new(StringIO.new).tap do |l|
      l.level = Logger::UNKNOWN
    end

    adapter_klass = server.config.pubsub_adapter

    @rx_adapter = adapter_klass.new(server)
    @tx_adapter = adapter_klass.new(server)

    @tx_adapter.shutdown
    @tx_adapter = @rx_adapter
  end

  teardown do
    [@rx_adapter, @tx_adapter].uniq.compact.each(&:shutdown)
  end

  test "subscribe_and_unsubscribe" do
    subscribe_as_queue("channel") do |queue|
    end
  end

  test "basic_broadcast" do
    subscribe_as_queue("channel") do |queue|
      @tx_adapter.broadcast("channel", "hello world")

      assert_equal "hello world", next_message_in_queue(queue)
    end
  end

  test "broadcast_after_unsubscribe" do
    keep_queue = nil
    subscribe_as_queue("channel") do |queue|
      keep_queue = queue

      @tx_adapter.broadcast("channel", "hello world")

      assert_equal "hello world", next_message_in_queue(queue)
    end

    @tx_adapter.broadcast("channel", "hello void")

    sleep WAIT_WHEN_NOT_EXPECTING_EVENT
    assert_empty keep_queue
  end

  test "trims_after_unsubscribe" do
    SolidCable.stub(:trim_chance, 99.999999) do
      with_cable_config message_retention: "2.seconds", trim_batch_size: 2 do
        subscribe_as_queue("channel") do |queue|
          4.times do
            @tx_adapter.broadcast("channel", "hello world")
            sleep 3
          end

          queue.clear
        end
        assert_equal 1, SolidCable::Message.where(channel: "channel").count
      end
    end
  end

  test "multiple_broadcast" do
    subscribe_as_queue("channel") do |queue|
      @tx_adapter.broadcast("channel", "bananas")
      @tx_adapter.broadcast("channel", "apples")

      received = []
      2.times { received << next_message_in_queue(queue) }
      assert_equal %w(apples bananas), received.sort
    end
  end

  test "identical_subscriptions" do
    subscribe_as_queue("channel") do |queue|
      subscribe_as_queue("channel") do |queue_2|
        @tx_adapter.broadcast("channel", "hello")

        assert_equal "hello", next_message_in_queue(queue_2)
      end

      assert_equal "hello", next_message_in_queue(queue)
    end
  end

  test "simultaneous_subscriptions" do
    subscribe_as_queue("channel") do |queue|
      subscribe_as_queue("other channel") do |queue_2|
        @tx_adapter.broadcast("channel", "apples")
        @tx_adapter.broadcast("other channel", "oranges")

        assert_equal "apples", next_message_in_queue(queue)
        assert_equal "oranges", next_message_in_queue(queue_2)
      end
    end
  end

  test "channel_filtered_broadcast" do
    subscribe_as_queue("channel") do |queue|
      @tx_adapter.broadcast("other channel", "one")
      @tx_adapter.broadcast("channel", "two")

      assert_equal "two", next_message_in_queue(queue)
    end
  end

  test "long_identifiers" do
    channel_1 = "#{'a' * 100}1"
    channel_2 = "#{'a' * 100}2"
    subscribe_as_queue(channel_1) do |queue|
      subscribe_as_queue(channel_2) do |queue_2|
        @tx_adapter.broadcast(channel_1, "apples")
        @tx_adapter.broadcast(channel_2, "oranges")

        assert_equal "apples", next_message_in_queue(queue)
        assert_equal "oranges", next_message_in_queue(queue_2)
      end
    end
  end

  test "does not raise error when polling with no Active Record logger" do
    with_active_record_logger(nil) do
      assert_nothing_raised do
        subscribe_as_queue("channel") do |queue|
          @tx_adapter.broadcast("channel", "hello world")

          assert_equal "hello world", next_message_in_queue(queue)
        end
      end
    end
  end

  test "does not send old messages" do
    @tx_adapter.broadcast("channel", "channel1")
    @tx_adapter.broadcast("channel", "channel2")

    subscribe_as_queue("channel") do |queue|
      assert_empty queue

      @tx_adapter.broadcast("channel", "channel3")
      @tx_adapter.broadcast("channel", "channel4")
      @tx_adapter.broadcast("other", "other1")
      @tx_adapter.broadcast("other", "other2")

      subscribe_as_queue("other") do |other_queue|
        assert_empty other_queue
      end
      assert_equal "channel3", next_message_in_queue(queue)
      assert_equal "channel4", next_message_in_queue(queue)
    end

    @tx_adapter.broadcast("channel", "channel5")
    @tx_adapter.broadcast("channel", "channel6")

    subscribe_as_queue("channel") do |queue|
      assert_empty queue
    end
  end

  test "retries after a connection failure and keeps listening" do
    with_cable_config reconnect_attempts: [0] do
      raised = false
      original = SolidCable::Message.method(:broadcastable)

      SolidCable::Message.stub(:broadcastable, lambda { |channels, last_id|
        if raised
          original.call(channels, last_id)
        else
          raised = true
          raise ActiveRecord::ConnectionFailed, "boom"
        end
      }) do
        subscribe_as_queue("reconnect-channel") do |queue|
          @tx_adapter.broadcast("reconnect-channel", "hello")

          assert_equal "hello", next_message_in_queue(queue)
        end
      end

      assert raised
    end
  end

  private
    def cable_config
      { adapter: "solid_cable", message_retention: "1.second",
        polling_interval: "0.01.seconds" }
    end

    def subscribe_as_queue(channel, adapter = @rx_adapter)
      queue = Queue.new

      callback = ->(data) { queue << data }
      subscribed = Concurrent::Event.new
      adapter.subscribe(channel, callback, proc { subscribed.set })
      subscribed.wait(WAIT_WHEN_EXPECTING_EVENT)
      sleep WAIT_WHEN_EXPECTING_EVENT
      assert_predicate subscribed, :set?

      yield queue

      sleep WAIT_WHEN_NOT_EXPECTING_EVENT
      assert_empty queue
    ensure
      adapter.unsubscribe(channel, callback) if subscribed.set?
    end

    def with_active_record_logger(logger)
      old_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = logger
      yield
    ensure
      ActiveRecord::Base.logger = old_logger
    end

    def next_message_in_queue(queue)
      Timeout.timeout(5, nil, "Failed to get next item in queue") { queue.pop }
    end
end
