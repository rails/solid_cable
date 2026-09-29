# frozen_string_literal: true

require "test_helper"
require "concurrent"

require "active_support/core_ext/hash/indifferent_access"

# Ids are assigned when an INSERT runs but become visible when it commits, so
# two writers can commit out of id order. These tests hold one INSERT's
# transaction open while a higher id commits, which needs two real database
# sessions: transactional tests would share one connection across threads.
class ActionCable::SubscriptionAdapter::SolidCableCommitOrderTest < ActionCable::TestCase
  self.use_transactional_tests = false

  WAIT_WHEN_EXPECTING_EVENT = 1
  WAIT_WHEN_NOT_EXPECTING_EVENT = 0.2

  setup do
    skip "SQLite serializes writers, so ids always commit in order" if sqlite?

    server = ActionCable::Server::Base.new
    server.config.cable = { adapter: "solid_cable", polling_interval: "0.01.seconds" }.with_indifferent_access
    server.config.logger = Logger.new(StringIO.new).tap { |l| l.level = Logger::UNKNOWN }

    @adapter = server.config.pubsub_adapter.new(server)
  end

  teardown do
    @adapter&.shutdown
    SolidCable::Message.delete_all
  end

  test "delivers a message that commits after a higher id" do
    subscribe_as_queue("channel") do |queue|
      with_open_insert("channel", "first") do
        SolidCable::Message.broadcast("channel", "second")

        # The listener has now read "second", an id above "first".
        assert_equal "second", next_message_in_queue(queue)
      end

      assert_equal "first", next_message_in_queue(queue)
    end
  end

  test "delivers a late message once" do
    subscribe_as_queue("channel") do |queue|
      with_open_insert("channel", "first") do
        SolidCable::Message.broadcast("channel", "second")
        assert_equal "second", next_message_in_queue(queue)
      end

      assert_equal "first", next_message_in_queue(queue)

      SolidCable::Message.broadcast("channel", "third")
      assert_equal "third", next_message_in_queue(queue)
    end
  end

  test "does not deliver a late message to a channel subscribed after its id" do
    subscribe_as_queue("channel") do |queue|
      with_open_insert("other channel", "early") do |commit|
        SolidCable::Message.broadcast("channel", "second")
        assert_equal "second", next_message_in_queue(queue)

        subscribe_as_queue("other channel") do |other_queue|
          commit.call
          sleep WAIT_WHEN_NOT_EXPECTING_EVENT
          assert_empty other_queue
        end
      end
    end
  end

  private
    def sqlite?
      SolidCable::Record.connection_db_config.adapter == "sqlite3"
    end

    # Inserts on its own connection and keeps the transaction open until the
    # block returns or calls the yielded commit, so an id drawn in between is
    # higher and commits first.
    def with_open_insert(channel, payload)
      inserted = Concurrent::Event.new
      release = Concurrent::Event.new

      writer = Thread.new do
        SolidCable::Record.connection_pool.with_connection do
          SolidCable::Record.transaction do
            SolidCable::Message.broadcast(channel, payload)
            inserted.set
            release.wait(5)
          end
        end
      end

      commit = -> { release.set; writer.join }

      assert inserted.wait(WAIT_WHEN_EXPECTING_EVENT), "the slow writer did not insert"
      yield commit
    ensure
      commit&.call
    end

    def subscribe_as_queue(channel)
      queue = Queue.new

      callback = ->(data) { queue << data }
      subscribed = Concurrent::Event.new
      @adapter.subscribe(channel, callback, proc { subscribed.set })
      subscribed.wait(WAIT_WHEN_EXPECTING_EVENT)
      assert_predicate subscribed, :set?

      yield queue

      sleep WAIT_WHEN_NOT_EXPECTING_EVENT
      assert_empty queue
    ensure
      @adapter.unsubscribe(channel, callback) if subscribed&.set?
    end

    def next_message_in_queue(queue)
      Timeout.timeout(5, nil, "Failed to get next item in queue") { queue.pop }
    end
end
