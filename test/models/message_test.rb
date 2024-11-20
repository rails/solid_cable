require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "broadcasts" do
    SolidCable::Record.connects_to database: { reading: :other, writing: :primary }

    assert_difference -> { SolidCable::Message.count } do
      SolidCable::Message.broadcast("foo", "bar")
    end

    SolidCable::Record.connects_to database: { reading: :primary, writing: :primary }
  end
end
