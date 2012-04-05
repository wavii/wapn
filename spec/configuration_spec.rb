require "wapn/configuration"

describe WAPN::Configuration do

  let(:root) { Module.new.tap {|m| m.extend(described_class)} }

  context "w/ YAML file" do

    before(:each) do
      root.load_config(File.join(FIXTURES, "complex_configuration.yaml"))
    end

    it "should interpolate configs with ERB" do
      provider = root.provider(:awesomesauce)
      provider.gateway_host.should == "gateway.foo.bar.baz"
      provider.gateway_port.should == 54321
      provider.feedback_host.should == "feedback.push.baz.bar"
      provider.feedback_port.should == 9999
    end

    it "should default to the production APNs environment" do
      provider = root.provider(:default_env)
      provider.gateway_host.should == 'gateway.push.apple.com'
      provider.gateway_port.should == 2195
      provider.feedback_host.should == 'feedback.push.apple.com'
      provider.feedback_port.should == 2196
    end

    it "should treat the environment key as a shorthand for setting standard gateway/feedback values" do
      sandbox_provider = root.provider(:sandbox_env)
      sandbox_provider.gateway_host.should == 'gateway.sandbox.push.apple.com'
      sandbox_provider.gateway_port.should == 2195
      sandbox_provider.feedback_host.should == 'feedback.sandbox.push.apple.com'
      sandbox_provider.feedback_port.should == 2196

      prod_provider = root.provider(:prod_env)
      prod_provider.gateway_host.should == 'gateway.push.apple.com'
      prod_provider.gateway_port.should == 2195
      prod_provider.feedback_host.should == 'feedback.push.apple.com'
      prod_provider.feedback_port.should == 2196
    end

    it "should expand the cert_bundle key into certificate_path and private_key_path" do
      provider = root.provider(:default_env)

      provider.certificate_path.should == 'cert_bundle.pem'
      provider.private_key_path.should == 'cert_bundle.pem'
    end

    it "should honor the log_level key" do
      provider = root.provider(:awesomesauce)

      provider.logger.level.should == Logger::DEBUG
    end

    it "should provide a batch_all helper" do
      root.providers.values.each do |provider|
        provider.should_receive(:begin_batch).once
        provider.should_receive(:commit_batch).once
      end

      root.batch_all { }
    end

  end

end
