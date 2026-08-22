module SolidCable
  class Configuration
    def initialize(**options)
      @options = ActiveSupport::InheritableOptions.new(options)
    end

    attr_writer :connects_to, :silence_polling, :polling_interval,
      :message_retention, :autotrim, :trim_batch_size, :use_skip_locked,
      :reconnect_attempts, :writer_batch_size, :writer_batch_delay,
      :encrypt, :encryption_context_properties

    def connects_to
      @connects_to ||= options.connects_to.to_h.deep_transform_values(&:to_sym)
    end

    def silence_polling?
      return @silence_polling if defined?(@silence_polling)

      @silence_polling = options.silence_polling != false
    end

    def polling_interval
      @polling_interval ||=
        parse_duration(options.polling_interval, default: 0.1.seconds)
    end

    def message_retention
      @message_retention ||= parse_duration(options.message_retention, default: 1.day)
    end

    def autotrim?
      return @autotrim if defined?(@autotrim)

      @autotrim = options.autotrim != false
    end

    def trim_batch_size
      @trim_batch_size ||=
        if (size = options.trim_batch_size.to_i) < 2
          100
        else
          size
        end
    end

    def use_skip_locked
      return @use_skip_locked if defined?(@use_skip_locked)

      @use_skip_locked = options.use_skip_locked != false
    end

    def reconnect_attempts
      @reconnect_attempts ||= begin
        attempts = options[:reconnect_attempts] || 1
        attempts = Array.new(attempts, 0) if attempts.is_a?(Integer)
        attempts
      end
    end

    def writer_batch_size
      @writer_batch_size ||= [ (options.writer_batch_size || 4).to_i, 1 ].max
    end

    def writer_batch_delay
      @writer_batch_delay ||=
        [ parse_duration(options.writer_batch_delay, default: 0.001.seconds), 0 ].max
    end

    def encrypt?
      return @encrypt if defined?(@encrypt)

      @encrypt = options.encrypt.present?
    end

    def encryption_context_properties
      return @encryption_context_properties if defined?(@encryption_context_properties)

      @encryption_context_properties = options.encryption_context_properties&.deep_symbolize_keys
      @encryption_context_properties ||= default_encryption_context_properties if encrypt?
    end

    private
      attr_reader :options

      def default_encryption_context_properties
        require "active_record/encryption/message_pack_message_serializer"

        {
          encryptor: ActiveRecord::Encryption::Encryptor.new(compress: true),
          # Binary column only serializer that is 40% more efficient than the default MessageSerializer
          message_serializer: ActiveRecord::Encryption::MessagePackMessageSerializer.new
        }
      end

      def parse_duration(duration, default:)
        if duration.present?
          *amount, units = duration.to_s.split(".")
          amount.join(".").to_f.public_send(units)
        else
          default
        end
      end
  end
end
