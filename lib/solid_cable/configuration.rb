module SolidCable
  class Configuration
    def initialize(**options)
      @options = ActiveSupport::InheritableOptions.new(options)
    end

    attr_writer :connects_to, :silence_polling, :polling_interval,
      :message_retention, :autotrim, :trim_batch_size, :use_skip_locked,
      :trim_chance, :reconnect_attempts, :use_batch_writer,
      :writer_batch_size, :writer_batch_delay

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

    # For every write that we do, we attempt to delete trim_chance times as
    # many records. This ensures there is downward pressure on the cache size
    # while there is valid data to delete. Read this as 'every time the trim job
    # runs theres a trim_multiplier chance this trims'. Adjust number to make it
    # more or less likely to trim. Only works like this if trim_batch_size is
    # 100
    def trim_chance
      2
    end

    def reconnect_attempts
      @reconnect_attempts ||= begin
        attempts = options[:reconnect_attempts] || 1
        attempts = Array.new(attempts, 0) if attempts.is_a?(Integer)
        attempts
      end
    end

    def use_batch_writer?
      return @use_batch_writer if defined?(@use_batch_writer)

      @use_batch_writer = options.use_batch_writer != false
    end

    def writer_batch_size
      @writer_batch_size ||= [ (options.writer_batch_size || 4).to_i, 1 ].max
    end

    def writer_batch_delay
      @writer_batch_delay ||=
        [ parse_duration(options.writer_batch_delay, default: 0.001.seconds), 0 ].max
    end

    private
      attr_reader :options

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
