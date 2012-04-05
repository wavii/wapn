# # WAPN::Payload
module WAPN
  class Payload

    APNS_ROOT = "aps"

    # An abstraction around the APNs JSON format for payloads.
    def initialize(options={})
      options        = Hash[ options.map { |k,v| [k.to_s, v] } ]
      custom_options = options.delete("custom")
      @apns_hash     = {}

      # The basic `apns` properties are supported; they are exactly the same as what Apple
      # specifies.
      #
      # * `alert`: A string or hash (for localized alerts)
      # * `badge`: A numeric value to display as the app's badge value
      # * `sound`: The name of a sound file in your app's bundle.
      @apns_hash[APNS_ROOT] = options

      # Additional options must be passed via the `custom` key (every other top level option is
      # merged into the `apns` namespace for future compatibility).
      #
      # * `custom`: Any app-specific properties you would like to pass are grouped into this option.
      #             Custom values are merged into the root of the payload (thus, `apns` cannot be
      #             used as a custom property)
      if custom_options
        custom_hash = Hash[ custom_options.map { |k,v| [k.to_s, v] } ]
        custom_hash.keys.each do |key|
          raise "'#{key}' is a reserved property, and cannot be specified in :custom!" if options.has_key? key
        end

        @apns_hash.merge! custom_hash
      end
    end

    # ## Validation & Cleanup

    # Apple has a hard limit of 256 characters for an entire notification message, 45 of which is
    # consumed by notification headers & metadata (extended format).  This leaves room for 211 bytes
    # of JSON data.
    MAX_PAYLOAD_LENGTH = 211

    def valid_length?
      self.apns_json.bytesize <= MAX_PAYLOAD_LENGTH
    end

    # If your payload is too large, truncate the alert and replace the last few characters will
    # filler, such as an ellipsis.
    DEFAULT_TRUNCATION_FILLER = "\xe2\x80\xa6".force_encoding("utf-8") # "…"

    def truncate_alert!(trailing_fill=DEFAULT_TRUNCATION_FILLER)
      # require "ruby-debug"; debugger
      payload_size = self.apns_json.bytesize
      return unless payload_size > MAX_PAYLOAD_LENGTH

      alert = @apns_hash[APNS_ROOT]["alert"]
      alert = alert[:body] || alert["body"] if alert.is_a? Hash
      unless alert.is_a? String
        raise "No valid alert to trim!  Can only trim a String or alert body.  (alert is #{alert.inspect})"
      end

      target_alert_size = alert.bytesize - (payload_size - MAX_PAYLOAD_LENGTH) - trailing_fill.bytesize

      if target_alert_size < 0
        raise "Too many bytes in the rest of the payload; not enough to trim!"
      end

      size_count = 0
      stop_index = alert.chars.find_index { |c| size_count += c.bytesize; size_count > target_alert_size }

      alert[stop_index..-1] = trailing_fill
    end

    # ## Conversation for Delivery

    # The generated JSON for APNs
    def apns_json
      require "json"

      @apns_hash.to_json.encode("utf-8")
    end

    # The hash we are using to generate `apns_json` from.  This is primarily for testing purposes.
    attr_reader :apns_hash

  end
end
