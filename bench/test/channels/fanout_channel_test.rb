require "test_helper"

class FanoutChannelTest < ActionCable::Channel::TestCase
  test "subscribes to the requested stream" do
    subscribe stream: "presentation"

    assert subscription.confirmed?
    assert_has_stream "fanout:presentation"
  end

  test "publishes to every subscriber on the stream" do
    subscribe stream: "presentation"

    assert_broadcast_on(
      "fanout:presentation",
      { sequence: 7, sent_at: 1234, message: "hello" }
    ) do
      perform :publish, sequence: 7, sent_at: 1234, message: "hello"
    end
  end

  test "publishes the completion marker" do
    subscribe stream: "presentation"

    assert_broadcast_on("fanout:presentation", { complete: true }) do
      perform :publish, complete: true
    end
  end
end
