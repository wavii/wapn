require "wapn/provider"
require "wapn/payload"
require "wapn/connection"
require "wapn/notification"

describe WAPN::Provider do

  before(:each) do
    WAPN::Provider.any_instance.stub(:log_output_target) {
      double.tap { |d| d.stub(:write); d.stub(:close) }
    }
  end

  context "when fully configured" do
    let(:provider) {
      described_class.new(
        cert_bundle_path: File.join(FIXTURES, "fake_bundle.pem"),
        retry_backoff:   [1.5, 3.6, 12.6, 30.5],
        error_skip_delay: 26.0,
        delay_for_errors: 11.5,
      )
    }

    before(:each) do
      connection_double = double
      WAPN::Connection.stub(:new) { connection_double }

      connection_double.stub(:flush)
      connection_double.stub(:socket) { connection_double }
      connection_double.stub(:with_socket) { |&block| block.call(connection_double) }

      IO.stub(:select)
    end

    it "should provide a helper for easy notification sending" do
      provider.gateway_connection.socket.should_receive(:write).once

      provider.notify("some_device_token", alert: "hi")
    end

    it "should provide a helper for batching notifications" do
      provider.batch do
        provider.notify("some_device_token", alert: "message 1")
        provider.notify("some_device_token", alert: "message 2")

        provider.gateway_connection.socket.should_receive(:write).twice
      end
    end

    it "should not mistakenly defer batches" do
      provider.gateway_connection.socket.should_receive(:write).exactly(4).times

      provider.batch do
        provider.notify("some_device_token", alert: "message 1")
        provider.notify("some_device_token", alert: "message 2")
      end

      provider.batch do
        provider.notify("some_device_token", alert: "message 3")
        provider.notify("some_device_token", alert: "message 4")
      end
    end

    it "should let you send the same payload to multiple devices" do
      provider.gateway_connection.socket.should_receive(:write).twice

      provider.notify(["device1", "device2"], alert: "stuff.")
    end

    it "should accept Payload objects instead of an options hash" do
      provider.gateway_connection.socket.should_receive(:write).once

      payload = WAPN::Payload.new(alert: "message", badge: 2)
      provider.notify("some_device_token", payload)
    end

    it "should retry on unknown errors, with proper delay" do
      provider.gateway_connection.socket.should_receive(:write).exactly(5).times.and_raise("fail!")
      provider.gateway_connection.should_receive(:close!).exactly(5).times
      provider.should_receive(:sleep).once.ordered.with(1.5)
      provider.should_receive(:sleep).once.ordered.with(3.6)
      provider.should_receive(:sleep).once.ordered.with(12.6)
      provider.should_receive(:sleep).once.ordered.with(30.5)

      provider.notify("some_device_token", alert: "ohai")
    end

    it "should stop retrying on success" do
      provider.gateway_connection.socket.should_receive(:write).once.ordered.and_raise("fail!")
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(1.5)

      provider.gateway_connection.socket.should_receive(:write).once.ordered.and_raise("fail!")
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(3.6)

      provider.gateway_connection.socket.should_receive(:write).once.ordered

      provider.notify("some_device_token", alert: "ohai")
    end

    it "should look for delivery errors in the socket, and kill the connection if found (causing a retry)" do
      provider.gateway_connection.socket.should_receive(:write).once.ordered
      IO.should_receive(:select).once.ordered { |reads, writes, errors, delay|
        delay.should == 0.0
        [true, nil, nil]
      }
      provider.gateway_connection.socket.should_receive(:read) { "" }.once.ordered
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(1.5)
      provider.gateway_connection.socket.should_receive(:write).once.ordered
      IO.should_receive(:select).once.ordered

      provider.notify("some_device_token", alert: "ohai")
    end

    it "should gracefully handle exceptions thrown when reading for errors" do
      provider.gateway_connection.socket.should_receive(:write).once.ordered
      IO.should_receive(:select).once.ordered { |reads, writes, errors, delay|
        delay.should == 0.0
        [true, nil, nil]
      }
      provider.gateway_connection.socket.should_receive(:read).once.ordered.and_raise("fail!")
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(1.5)
      provider.gateway_connection.socket.should_receive(:write).once.ordered
      IO.should_receive(:select).once.ordered

      provider.notify("some_device_token", alert: "ohai")
    end

    it "should deserialize delivery errors & skip that notification" do
      notifications = 5.times.map {
        WAPN::Notification.new("some_device", WAPN::Payload.new(alert: "stuff"))
      }
      packets = notifications.map(&:to_packet)

      IO.should_receive(:select) { |reads, writes, errors, delay|
        delay.should == 11.5
        [true, nil, nil]
      }

      5.times.each do |i|
        provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[i])
      end
      provider.gateway_connection.socket.should_receive(:read) {
        [8, 8, notifications[1].identifier].pack("ccN")
      }.ordered
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(26.0)

      provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[2])
      provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[3])
      provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[4])

      provider.send_notifications(notifications)
    end

    it "should not skip notifications if it cannot find one to skip" do
      notifications = 5.times.map {
        WAPN::Notification.new("some_device", WAPN::Payload.new(alert: "stuff"))
      }
      packets = notifications.map(&:to_packet)

      IO.should_receive(:select) { |reads, writes, errors, delay|
        delay.should == 11.5
        [true, nil, nil]
      }

      5.times.each do |i|
        provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[i])
      end
      provider.gateway_connection.socket.should_receive(:read) {
        [8, 8, notifications.last.identifier + 1].pack("ccN")
      }.ordered
      provider.gateway_connection.should_receive(:close!).once.ordered
      provider.should_receive(:sleep).once.ordered.with(1.5)

      5.times.each do |i|
        provider.gateway_connection.socket.should_receive(:write).once.ordered.with(packets[i])
      end

      provider.send_notifications(notifications)
    end

  end

  context "in a default state" do
    let(:provider) { described_class.new }

    it "should bet set to a to a WARN log level" do
      provider.log_level.should == :warn
      provider.logger.level.should == Logger::WARN
    end

    it "should default to the production APNs environment" do
      provider.gateway_host.should == 'gateway.push.apple.com'
      provider.gateway_port.should == 2195
      provider.feedback_host.should == 'feedback.push.apple.com'
      provider.feedback_port.should == 2196
    end

  end

  it "should expose its SSL cert & private key as OpenSSL objects" do
    provider = described_class.new(cert_bundle_path: File.join(FIXTURES, "fake_bundle.pem"))

    encrypted = provider.ssl_private_key.private_encrypt("just testing!")
    provider.ssl_certificate.public_key.public_decrypt(encrypted).should == "just testing!"
  end

  it "should support encrypted private keys" do
    provider = described_class.new(
      certificate_path: File.join(FIXTURES, "fake_secured_cert.pem"),
      private_key_path: File.join(FIXTURES, "fake_secured_pk.pem"),
      private_key_pass: "12345",
    )

    encrypted = provider.ssl_private_key.private_encrypt("just testing!")
    provider.ssl_certificate.public_key.public_decrypt(encrypted).should == "just testing!"
  end

  it "should give a helpful error if you forget a private key password" do
    provider = described_class.new(
      certificate_path: File.join(FIXTURES, "fake_secured_cert.pem"),
      private_key_path: File.join(FIXTURES, "fake_secured_pk.pem"),
    )

    expect { provider.ssl_private_key }.to raise_error(/Did you forget or set the wrong private_key_pass\?/)
  end

  it "should not expose PK and certificate info via inspect or to_s" do
    OpenSSL::X509::Certificate.stub(:new) { "<<SSL_CERTIFICATE>>" }
    OpenSSL::PKey::RSA.stub(:new) { "<<SSL_PRIVATE_KEY>>" }

    provider = described_class.new

    provider.stub(:open) { double.tap { |d| d.stub(:read) } }
    provider.ssl_certificate
    provider.ssl_private_key

    provider.to_s.should_not include("<<SSL_CERTIFICATE>>")
    provider.to_s.should_not include("<<SSL_PRIVATE_KEY>>")

    provider.inspect.should_not include("<<SSL_CERTIFICATE>>")
    provider.inspect.should_not include("<<SSL_PRIVATE_KEY>>")
  end

end
