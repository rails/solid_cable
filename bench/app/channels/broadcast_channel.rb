class BroadcastChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "a client subscribed: #{id}"
    stream_from "broadcast:#{id}"
  end

  def unsubscribed
    Rails.logger.info "unsubscribed: #{id}"
    stop_all_streams
  end

  def ping(data)
    broadcast_to id, { message: "pong #{data.with_indifferent_access[:message]}" }
  end
end
