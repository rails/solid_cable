# frozen_string_literal: true

require "test_helper"
require "config_stubs"

class TrimJobTest < ActiveJob::TestCase
  include ConfigStubs

  test "trims a limited number of messages" do
    SolidCable.stub(:trim_chance, 99.999) do
      with_cable_config trim_batch_size: 2, message_rention: "1.second" do
        4.times do
          SolidCable::Message.broadcast("foo", "bar")
          SolidCable::Message.update_all(created_at: 2.days.ago)
        end

        assert_difference -> { SolidCable::Message.count }, -4 do
          SolidCable::TrimJob.perform_now
        end
      end
    end
  end
end
