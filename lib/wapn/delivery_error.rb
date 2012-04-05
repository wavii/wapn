module WAPN
  class DeliveryError

    FAILURE_REASONS = {
      nil => "Unknown reason (no response from APNs)",
      0   => "APNs Error: No errors encountered", # Seriously?
      1   => "APNs Error: Processing Error",
      2   => "APNs Error: Missing device token",
      3   => "APNs Error: Missing topic",
      4   => "APNs Error: Missing payload",
      5   => "APNs Error: Invalid token size",
      6   => "APNs Error: Invalid topic size",
      7   => "APNs Error: Invalid payload size",
      8   => "APNs Error: Invalid token",
      255 => "APNs Error: Unknown error",
    }

    def initialize(error_code=nil, identifier=nil)
      @error_code = error_code
      @identifier = identifier
    end

    attr_reader :error_code
    attr_reader :identifier

    def reason
      FAILURE_REASONS[@error_code] || "Unknown reason"
    end

    def inspect
      "#<#{self.class.name} '#{self.reason}' @identifier=#{@identifier.inspect}>"
    end

    class << self

      def from_bytes(bytes)
        return self.new unless bytes && bytes.bytesize >= 6

        result = bytes.unpack("ccN")
        self.new(result[1], result[2])
      end

    end

  end
end
