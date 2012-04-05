require "wapn/notification"
require "wapn/payload"

describe WAPN::Notification do

  let(:device_token) { "674ec898798cba3a21f6de31965f733895d9c48751580d5c33d343f6cb0fa005" }
  def binary_device_token
    [device_token].pack("H*").bytes.to_a
  end

  def assert_valid_extended_packet(notification, payload_json, timestamp=nil)
    payload_length = payload_json.bytesize

    identifier = [notification.identifier].pack("N").bytes.to_a
    timestamp  = [timestamp || notification.expiration_time.to_i].pack("N").bytes.to_a

    notification.to_packet.bytes.to_a.should ==
      [1] + identifier + timestamp + [0, 32] + binary_device_token +
      [0, payload_length] + payload_json.bytes.to_a
  end

  it "should serialize simple payloads" do
    payload      = WAPN::Payload.new(alert: "hi", badge: 5)
    payload_json = payload.apns_json

    notification = described_class.new(device_token, payload)
    assert_valid_extended_packet(notification, payload_json)
  end

  it "should support custom expiration times" do
    payload      = WAPN::Payload.new(alert: "hi", badge: 5)
    payload_json = payload.apns_json

    notification = described_class.new(device_token, payload, Time.utc(2001))
    assert_valid_extended_packet(notification, payload_json, 978307200)
  end

  it "should not explode after sending 18,446,744,073,709,551,616 or more notifications" do
    WAPN::Notification.instance_variable_set(:@notification_count, 18446744073709551615)

    payload      = WAPN::Payload.new(alert: "hi", badge: 5)
      payload_json = payload.apns_json

    5.times do
      notification = described_class.new(device_token, payload)
      assert_valid_extended_packet(notification, payload_json)
    end
  end

end
