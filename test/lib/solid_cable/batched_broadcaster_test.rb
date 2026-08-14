# frozen_string_literal: true

require "test_helper"

class SolidCable::BatchedBroadcasterTest < ActiveSupport::TestCase
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
