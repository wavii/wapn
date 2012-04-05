module WAPN
  class Notification

    attr_reader :identifier
    attr_reader :device_token
    attr_reader :payload
    attr_reader :expiration_time

    def initialize(device_token, payload, expiration_time=Time.now + 3600)
      # An integer >= 0 && <= 2^64 - 1.  E.g. 64-bit unsigned integer.
      @identifier = self.class.next_identifier

      @device_token    = device_token
      @payload         = payload
      @expiration_time = expiration_time
    end

    # The notification in binary form
    def to_packet
      token_length = self.device_token.size / 2 # The binary length
      payload = self.payload.apns_json

      [1, self.identifier, self.expiration_time.to_i, token_length, self.device_token, payload.bytesize, payload].pack("cNNnH*na*")
    end

    class << self

      # Each notification gets a unique identifier so that we can associate errors with them.
      #
      # This is an incrementing 64-bit integer; so you have to send 2^64 notifications before
      # identifiers wrap;  If you're running into problems due to repeated identifiers, you've
      # probably just DoSed the APN service; congratulations!
      def next_identifier
        @notification_count ||= 0
        @notification_count  += 1

        @notification_count % 2**64
      end

    end

  end
end
