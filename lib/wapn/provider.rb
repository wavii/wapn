# # WAPN::Provider
require "wapn/connection"
require "wapn/delivery_error"
require "wapn/notification"
require "wapn/payload"

module WAPN

  # A `Provider` is an abstraction around the APNs concept of providers.
  class Provider

    STANDARD_ENVIRONMENTS = {
      production: {
        gateway_host:  "gateway.push.apple.com",
        gateway_port:   2195,
        feedback_host: "feedback.push.apple.com",
        feedback_port:  2196,
      },
      sandbox: {
        gateway_host:  "gateway.sandbox.push.apple.com",
        gateway_port:   2195,
        feedback_host: "feedback.sandbox.push.apple.com",
        feedback_port:  2196,
      },
    }

    # ## Provider.new
    #
    # Supported options are:
    def initialize(options={})
      options = Hash[ options.map { |k,v| [k.to_sym, v] } ]

      # * `cert_bundle_path`: If you have both the client certificate and private key in a single
      #                       PEM bundle, use this as shorthand for setting both `certificate_path`
      #                       and `private_key_path` to the same value.
      if cert_bundle_path = options.delete(:cert_bundle_path)
        options[:certificate_path] = cert_bundle_path
        options[:private_key_path] = cert_bundle_path
      end

      # * `certificate_path`: The path to your PEM-encoded APNs certificate provided by Apple.
      @certificate_path = options[:certificate_path]
      # * `private_key_path`: The path to your PEM-encoded private key associated w/ your APNs cert.
      @private_key_path = options[:private_key_path]
      # * `private_key_pass`: The password to your private key if it is encrypted.
      @private_key_pass = options[:private_key_pass]

      # * environment: Shorthand for gateway and feedback values.  You can specify `standbox` or
      #                `production` and the standard Apple service configuration will be filled in.
      if environment = options.delete(:environment)
        raise "Unknown APNs environment '#{environment}'!" unless STANDARD_ENVIRONMENTS[environment.to_sym]

        options.merge! STANDARD_ENVIRONMENTS[environment.to_sym]
      end

      # If you do not specify endpoint configuration or environment, the provider defaults to the
      # `production` APNs environment.
      if (options.keys & [:gateway_host, :gateway_port, :feedback_host, :feedback_port]).size == 0
        options.merge! STANDARD_ENVIRONMENTS[:production]
      end

      # * `gateway_host`:  Hostname to use for contacting the gateway service.
      @gateway_host = options[:gateway_host]
      # * `gateway_port`:  Port of the gateway service.
      @gateway_port = options[:gateway_port].to_i
      # * `feedback_host`: Hostname to user for contacting the feedback service.
      @feedback_host = options[:feedback_host]
      # * `feedback_port`: Port of the feedback service.
      @feedback_port = options[:feedback_port].to_i

      # * `name`: An identifier for this provider; used for debugging and inspection.
      @name = (options[:name] || "unknown").to_s

      # * `log_level`: How verbose logging should be.  `debug`, `info`, `warn`, or `error`.
      @log_level         = options[:log_level] ? options[:log_level].to_sym : :warn
      # * `log_output_io`: An IO object or path that the logger should write to.
      @log_output_target = options[:log_output_target] || $stdout

      # * `delay_for_errors`: Due to the asychronous nature of APNs protocol, we must wait for a
      #                       short while for an error response if we want to be able to continue
      #                       sending large batches of notifications.  This determines how long in
      #                       seconds that we should wait for an error.  The longer you wait, you
      #                       are less likely to skip good notifications.
      @delay_for_errors = options[:delay_for_errors] || 1.0
      # * `error_skip_delay`: When we encounter an APNs error for a given notification, how long
      #                       should we delay before resuming the batch after that bad one?
      @error_skip_delay = options[:error_skip_delay] || 0.5

      # * `retry_backoff`: An array of numeric values indicating the # of retries and the delay
      #                    between each.  This backoff strategy applies to all non-APNs errors.
      @retry_backoff = options[:retry_backoff] || [0.25, 0.75, 2.5]
    end

    # ## Public Properties

    # Identification and security
    attr_reader :certificate_path
    attr_reader :private_key_path
    attr_reader :private_key_pass

    # Endpoint configuration
    attr_reader :gateway_host
    attr_reader :gateway_port
    attr_reader :feedback_host
    attr_reader :feedback_port

    # Misc configuration
    attr_reader :name
    attr_reader :log_level
    attr_reader :log_output_target

    # Error handling
    attr_reader :delay_for_errors
    attr_reader :error_skip_delay
    attr_reader :retry_backoff

    # Each provider has its own logger.
    #
    # You're welcome to set your own custom logger (such as a
    # [`Log4r::Logger`](http://log4r.rubyforge.org/rdoc/Log4r/Logger.html)).  It must respond to
    # `debug`, `info`, `warn`, and `error`.
    attr_writer :logger
    def logger
      @logger ||= begin
        require "logger"

        Logger.new(self.log_output_target).tap do |logger|
          logger.level = Logger::Severity.const_get(self.log_level.to_s.upcase)
          logger.formatter = proc { |severity, datetime, progname, message|
            timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S")
            "[#{timestamp}] #{self.class.name}(#{self.name}) #{severity.rjust(5)}: #{message}\n"
          }
        end
      end
    end

    # ## Notifications

    # Send a notification payload to one or more devices.
    #
    # You can either pass an options hash, or an explicit [`Payload`](payload.html) object.
    def notify(device_or_devices, payload_or_options)
      payload = payload_or_options.is_a?(Hash) ? Payload.new(payload_or_options) : payload_or_options

      notifications = Array(device_or_devices).map { |d| Notification.new(d, payload) }

      if @batch
        @batch += notifications
      else
        self.send_notifications(notifications)
      end
    end

    # Collects a batch of notifications from calls to `notify`, and bulk sends them when the block
    # returns.
    def batch(&block)
      @batch = []

      block.call

      self.send_notifications(@batch)
      @batch = nil
    end

    def send_notifications(notifications, attempt=0)
      return unless notifications.size > 0

      self.logger.debug "Sending batch of notifications:"
      notifications.each { |n| self.logger.debug("  #{n.inspect}") }

      packets = notifications.map(&:to_packet)
      exception, delivery_error = nil

      self.gateway_connection.with_socket do |socket|
        begin
          packets.each do |packet|
            self.logger.debug "  Sending packet: #{packet.inspect}"
            socket.write(packet)
          end
          socket.flush
        # Even if we are in an error state, we frequently will not get low-level errors due to TCP's
        # asynchronous nature.  Or, confusingly, we might have gotten an error from a previous batch
        # of notifications.
        rescue
          exception = $!
          self.logger.warn "Encountered error when sending notifications: #{exception}"
        end

        # So, we check for errors after a slight delay, so that we can continue sending the
        # the remaining notifications.  No delay if we know there can be no extra work.
        read_delay = notifications.size > 1 ? self.delay_for_errors : 0.0

        begin
          readable, _, _ = IO.select([socket], nil, nil, read_delay)
          read_bytes = socket.read if readable
        rescue
          exception = $!
        end

        if read_bytes
          delivery_error = DeliveryError.from_bytes(read_bytes)
          self.logger.warn "Received APNs delivery error: #{delivery_error.inspect}"
        end
      end

      if exception || delivery_error
        # Regardless of the kind of error we encountered, we need to reconnect
        self.gateway_connection.close!

        # If a notification in our current batch failed, let's try to continue by skipping it
        if delivery_error && failed_index = notifications.find_index { |n| n.identifier == delivery_error.identifier }
          self.logger.warn "Skipping failed notification due to error '#{delivery_error.inspect}': #{notifications[failed_index].inspect}"

          # This restarts retry attempts since it's effectively a new batch
          sleep(self.error_skip_delay)
          self.send_notifications Array(notifications[(failed_index + 1)..-1])

        # Otherwise, standard retry logic
        else
          return unless self.retry_backoff[attempt]
          sleep(self.retry_backoff[attempt])

          self.send_notifications(notifications, attempt + 1)
        end
      end
    end

    # ## Connection Management

    def gateway_connection
      @gateway_connection ||= Connection.new(
        self.gateway_host, self.gateway_port, self.ssl_certificate, self.ssl_private_key, self.logger
      )
    end

    def feedback_connection
      @gateway_connection ||= Connection.new(
        self.feedback_host, self.feedback_port, self.ssl_certificate, self.ssl_private_key, self.logger
      )
    end

    # The SSL client certificate that this connection will use.
    def ssl_certificate
      @ssl_certificate ||= begin
        require "openssl"

        self.logger.debug "Reading client certificate from #{self.certificate_path}"
        OpenSSL::X509::Certificate.new(open(self.certificate_path).read)
      end
    end

    # The private key associated with your client certificate.
    def ssl_private_key
      @ssl_private_key ||= begin
        require "openssl"

        begin
          # By passing an empty string, we force OpenSSL to *not* prompt you for a password if you
          # forget it.  We don't want stdin breaking your app's initialization process!
          self.logger.debug "Reading private key from #{self.private_key_path}"
          OpenSSL::PKey::RSA.new(open(self.private_key_path).read, self.private_key_pass || "")

        # OpenSSL doesn't give very useful errors
        rescue OpenSSL::PKey::RSAError => err
          self.logger.error "Failed to read private key from #{self.private_key_path}: #{err}"
          raise "Did you forget or set the wrong private_key_pass?  OpenSSL says: #{err}"
        end
      end
    end

    def inspect
      "#<#{self.class.name} #{self.name}>"
    end

  end

end
