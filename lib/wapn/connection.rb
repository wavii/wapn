# # WAPN::Connection
module WAPN

  class Connection

    def initialize(host, port, certificate, private_key, logger)
      @host        = host
      @port        = port
      @certificate = certificate
      @private_key = private_key
      @logger      = logger
    end

    def with_socket(&block)
      block.call(self.socket)
    end

    def socket
      return @ssl_sock if @ssl_sock && !@ssl_sock.closed?

      @logger.info "Opening connection to #{@host}:#{@port}"

      require "openssl"

      context      = OpenSSL::SSL::SSLContext.new
      context.cert = @certificate
      context.key  = @private_key

      @tcp_sock = TCPSocket.new(@host, @port)
      @ssl_sock = OpenSSL::SSL::SSLSocket.new(@tcp_sock, context)
      @ssl_sock.connect

      @ssl_sock
    end

    def close!
      @logger.info "Closing connection to #{@host}:#{@port}"

      @ssl_sock.close
      @tcp_sock.close
    end

    def inspect
      "#<#{self.class.name} #{@host}:#{@port}>"
    end

  end

end
