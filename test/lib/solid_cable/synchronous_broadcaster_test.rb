# frozen_string_literal: true

require "test_helper"
require "config_stubs"

class SolidCable::SynchronousBroadcasterTest < ActiveSupport::TestCase
  include ConfigStubs

  teardown do
    @broadcaster&.shutdown
  end

  test "writes in the calling thread before returning" do
    @broadcaster = SolidCable::SynchronousBroadcaster.new
    writes = []

    SolidCable::Message.stub(:broadcast, ->(channel, payload) { writes << [ channel, payload, Thread.current ] }) do
      @broadcaster.broadcast("channel", "payload")
      assert_equal [ [ "channel", "payload", Thread.current ] ], writes
    end
  end

  test "propagates write errors without retrying or trimming" do
    @broadcaster = SolidCable::SynchronousBroadcaster.new
    error = RuntimeError.new("write failed")
    attempts = 0

    SolidCable::Message.stub(:broadcast, ->(*) { attempts += 1; raise error }) do
      @broadcaster.stub(:track_writes, ->(*) { flunk "must not trim a failed write" }) do
        assert_same error, assert_raises(RuntimeError) { @broadcaster.broadcast("channel", "payload") }
      end
    end

    assert_equal 1, attempts
  end

  test "trims proportionally and asynchronously" do
    trims = Queue.new

    with_cable_config trim_batch_size: 2 do
      @broadcaster = SolidCable::SynchronousBroadcaster.new

      SolidCable::Message.stub(:broadcast, nil) do
        SolidCable::TrimJob.stub(:perform_now, -> { trims << Thread.current }) do
          2.times { @broadcaster.broadcast("channel", "payload") }
          @broadcaster.shutdown
        end
      end
    end

    assert_equal 2, trims.size
    2.times { assert_not_same Thread.current, trims.pop }
  end

  test "does not trim when autotrimming is disabled" do
    with_cable_config autotrim: false do
      @broadcaster = SolidCable::SynchronousBroadcaster.new

      SolidCable::Message.stub(:broadcast, :written) do
        @broadcaster.stub(:track_writes, ->(*) { flunk "must not trim" }) do
          assert_equal :written, @broadcaster.broadcast("channel", "payload")
        end
      end
    end
  end

  test "reports trim scheduling errors without failing the write" do
    @broadcaster = SolidCable::SynchronousBroadcaster.new
    error = RuntimeError.new("trim scheduling failed")
    reported = []

    Rails.error.stub(:report, ->(exception, **) { reported << exception }) do
      SolidCable::Message.stub(:broadcast, :written) do
        @broadcaster.stub(:track_writes, ->(*) { raise error }) do
          assert_equal :written, @broadcaster.broadcast("channel", "payload")
        end
      end
    end

    assert_equal [ error ], reported
  end

  test "reports asynchronous trim errors without failing the write" do
    error = RuntimeError.new("trim failed")
    reported = Queue.new

    with_cable_config trim_batch_size: 2 do
      @broadcaster = SolidCable::SynchronousBroadcaster.new

      Rails.error.stub(:report, ->(exception, **) { reported << exception }) do
        SolidCable::Message.stub(:broadcast, :written) do
          SolidCable::TrimJob.stub(:perform_now, -> { raise error }) do
            assert_equal :written, @broadcaster.broadcast("channel", "payload")
            @broadcaster.shutdown
          end
        end
      end
    end

    assert_same error, reported.pop
  end

  test "shutdown waits for an in-flight write and rejects further broadcasts" do
    @broadcaster = SolidCable::SynchronousBroadcaster.new
    entered = Queue.new
    release = Queue.new
    stopped = Queue.new
    writer = shutdown = nil

    SolidCable::Message.stub(:broadcast, ->(*) { entered << true; release.pop }) do
      writer = Thread.new { @broadcaster.broadcast("channel", "payload") }
      entered.pop
      shutdown = Thread.new { @broadcaster.shutdown; stopped << true }

      assert_nil stopped.pop(timeout: 0.05)
      release << true
      writer.value
      shutdown.value
      assert stopped.pop
    end

    @broadcaster.shutdown
    assert_raises(SolidCable::SynchronousBroadcaster::Stopped) do
      @broadcaster.broadcast("channel", "payload")
    end
  ensure
    release << true if release
    writer&.join
    shutdown&.join
  end
end
