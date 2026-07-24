# frozen_string_literal: true

require "test_helper"

class SolidCable::MessageTest < ActiveSupport::TestCase
  test "assigns consecutive ids within each channel" do
    SolidCable::Message.broadcast_batch([
      [ "one", "first" ],
      [ "two", "other" ],
      [ "one", "second" ]
    ])

    assert_equal [ 1, 2 ], channel_ids_for("one")
    assert_equal [ 1 ], channel_ids_for("two")

    SolidCable::Message.broadcast_batch([
      [ "one", "third" ],
      [ "two", "another" ]
    ])

    assert_equal [ 1, 2, 3 ], channel_ids_for("one")
    assert_equal [ 1, 2 ], channel_ids_for("two")
    assert_equal 3, channel_for("one").current_id
    assert_equal 2, channel_for("two").current_id
  end

  test "rolls back the channel counter when inserting messages fails" do
    assert_raises ActiveRecord::NotNullViolation do
      SolidCable::Message.broadcast_batch([ [ "one", nil ] ])
    end

    assert_nil channel_for("one")
  end

  private
    def channel_for(channel)
      SolidCable::Channel.find_by(id: SolidCable::Message.channel_hash_for(channel))
    end

    def channel_ids_for(channel)
      SolidCable::Message.where(channel: channel).order(:channel_id).pluck(:channel_id)
    end
end
