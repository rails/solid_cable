module ApplicationCable
  class Connection < ActionCable::Connection::Base
    rescue_from Exception do |error|
      Rails.error.report(e, handled: false,
                      source: "application.action_cable")
    end

    identified_by :id

    def connect
      self.id = SecureRandom.uuid
    end
  end
end
