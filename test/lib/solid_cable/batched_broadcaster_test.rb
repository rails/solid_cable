# frozen_string_literal: true

require "test_helper"
require "config_stubs"

class SolidCable::BatchedBroadcasterTest < ActiveSupport::TestCase
  include ConfigStubs

  teardown do
    @broadcaster&.shutdown
  end

  test "batches concurrent broadcasts" do
    @broadcaster = SolidCable::BatchedBroadcaster.new(batch_size: 2, batch_delay: 1)
    batches = Queue.new

    SolidCable::Message.stub(:broadcast_batch, ->(batch) { batches << batch }) do
      threads = [
        Thread.new { @broadcaster.broadcast("one", "first") },
        Thread.new { @broadcaster.broadcast("two", "second") }
      ]
      threads.each(&:join)
      @broadcaster.shutdown
    end

    assert_equal 1, batches.size
    assert_equal [ [ "one", "first" ], [ "two", "second" ] ], batches.pop.sort
  end

  test "rejects broadcasts after shutdown" do
    @broadcaster = SolidCable::BatchedBroadcaster.new(batch_size: 2, batch_delay: 0)
    @broadcaster.shutdown

    assert_raises(SolidCable::BatchedBroadcaster::Stopped) do
      @broadcaster.broadcast("channel", "payload")
    end
  end

  test "trims in proportion to the number of messages written" do
    trims = Queue.new

    with_cable_config trim_batch_size: 2 do
      @broadcaster = SolidCable::BatchedBroadcaster.new(batch_size: 2, batch_delay: 1)

      SolidCable::Message.stub(:broadcast_batch, nil) do
        SolidCable::TrimJob.stub(:perform_now, -> { trims << true }) do
          @broadcaster.broadcast("one", "first")
          @broadcaster.broadcast("two", "second")
          @broadcaster.shutdown
        end
      end
    end

    assert_equal 2, trims.size
  end

  test "trims asynchronously" do
    write_threads = Queue.new
    trim_threads = Queue.new

    with_cable_config trim_batch_size: 2 do
      @broadcaster = SolidCable::BatchedBroadcaster.new(batch_size: 1, batch_delay: 0)

      SolidCable::Message.stub(:broadcast_batch, ->(*) { write_threads << Thread.current }) do
        SolidCable::TrimJob.stub(:perform_now, -> { trim_threads << Thread.current }) do
          @broadcaster.broadcast("channel", "payload")
          @broadcaster.shutdown
        end
      end
    end

    assert_not_same write_threads.pop, trim_threads.pop
  end

  test "reports write errors" do
    @broadcaster = SolidCable::BatchedBroadcaster.new(batch_size: 1, batch_delay: 0)
    write_error = RuntimeError.new("write failed")
    reported_errors = Queue.new

    Rails.error.stub(:report, ->(error, **) { reported_errors << error }) do
      SolidCable::Message.stub(:broadcast_batch, ->(*) { raise write_error }) do
        @broadcaster.broadcast("channel", "payload")
        @broadcaster.shutdown
      end
    end

    assert_same write_error, reported_errors.pop
  end
end
