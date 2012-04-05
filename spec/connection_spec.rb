require "wapn/connection"

describe WAPN::Connection do

  let(:logger) { double.tap { |d| d.stub(:info) } }
  let(:connection) { described_class.new("some.fake.host", 12345, double, double, logger) }

  def tcp_sock
    @last_tcp_sock = double("TCP Socket").tap { |d| d.stub(:closed?) }
  end
  def ssl_sock
    @last_ssl_sock = double("SSL Socket").tap { |d| d.stub(:closed?); d.stub(:connect) }
  end

  before(:each) do
    TCPSocket.stub(:new) { tcp_sock }
    OpenSSL::SSL::SSLSocket.stub(:new) { ssl_sock }
  end

  it "should re-use sockets that are still open" do
    sock = connection.with_socket { |s| s }

    connection.with_socket { |s| s.should == sock }
  end

  it "should not re-use sockets that are closed" do
    sock = connection.with_socket { |s| s }
    sock.stub(:closed?) { true }

    connection.with_socket { |s| s.should_not == sock }
  end

  it "should call close on both sockets, in proper order when close! is called" do
    connection.socket

    @last_ssl_sock.should_receive(:close).once.ordered
    @last_tcp_sock.should_receive(:close).once.ordered

    connection.close!
  end

  it "should not expose PK and certificate info via inspect or to_s" do
    connection = described_class.new("some.fake.host", 12345, "<<SSL_CERTIFICATE>>", "<<SSL_PRIVATE_KEY>>", logger)

    connection.to_s.should_not include("<<SSL_CERTIFICATE>>")
    connection.to_s.should_not include("<<SSL_PRIVATE_KEY>>")

    connection.inspect.should_not include("<<SSL_CERTIFICATE>>")
    connection.inspect.should_not include("<<SSL_PRIVATE_KEY>>")
  end

end
