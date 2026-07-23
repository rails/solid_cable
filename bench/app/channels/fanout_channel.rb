class FanoutChannel < ApplicationCable::Channel
  def subscribed
    @stream_name = "fanout:#{params.fetch("stream")}"
    stream_from @stream_name
  end

  def publish(data)
    ActionCable.server.broadcast(
      @stream_name,
      data.slice("sequence", "sent_at", "message", "complete", "expected_messages")
    )
  end
end
