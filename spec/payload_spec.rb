# encoding: UTF-8

require "wapn/payload"

describe WAPN::Payload do

  let(:long_alert) { "0---------1---------2---------3---------4---------5---------6---------7---------8---------9---------10--------11--------12--------13--------14--------15--------16--------17--------18--------19--------20--------21--------22--------23--------24--------25--------26--------27--------28--------29--------" }

  it "should place top level keys into the apns namespace" do
    payload = described_class.new(foo: 1, bar: "baz")
    payload.apns_hash.should == {
      "aps" => {"foo" => 1, "bar" => "baz"}
    }
  end

  it "should place custom keys into the top level" do
    payload = described_class.new(alert: "hi", custom: {fizz: 1, buzz: "bazz"})
    payload.apns_hash.should == {
      "aps" => {"alert" => "hi"},
      "fizz" => 1,
      "buzz" => "bazz",
    }
  end

  it "should expose valid_length?" do
    described_class.new(foo: 1, bar: "baz").valid_length?.should == true

    described_class.new(alert: long_alert).valid_length?.should == false
  end

  context "with alert truncation" do

    it "should work for alerts with single byte characters" do
      payload = described_class.new(alert: long_alert)
      payload.truncate_alert!

      payload.apns_hash["aps"]["alert"].should == "0---------1---------2---------3---------4---------5---------6---------7---------8---------9---------10--------11--------12--------13--------14--------15--------16--------17--------18------…"
      payload.apns_json.bytesize.should == 211
    end

    it "should work for complex alert hashes" do
      payload = described_class.new(alert: {body: long_alert})
      payload.truncate_alert!

      payload.apns_hash["aps"]["alert"][:body].should == "0---------1---------2---------3---------4---------5---------6---------7---------8---------9---------10--------11--------12--------13--------14--------15--------16--------17-------…"
      payload.apns_json.bytesize.should == 211
    end

    it "should allow for a blank trailing fill" do
      payload = described_class.new(alert: long_alert)
      payload.truncate_alert! ""

      payload.apns_hash["aps"]["alert"].should == "0---------1---------2---------3---------4---------5---------6---------7---------8---------9---------10--------11--------12--------13--------14--------15--------16--------17--------18--------1"
      payload.apns_json.bytesize.should == 211
    end

    it "should allow for a custom trailing fill" do
      payload = described_class.new(alert: long_alert)
      payload.truncate_alert! "><><><>"

      payload.apns_hash["aps"]["alert"].should == "0---------1---------2---------3---------4---------5---------6---------7---------8---------9---------10--------11--------12--------13--------14--------15--------16--------17--------18--><><><>"
      payload.apns_json.bytesize.should == 211
    end

    it "should not break inside multibyte characters" do
      payload = described_class.new(alert: "人権の無視及び軽侮が、人類の良心を踏みにじった野蛮行為をもたらし、言論及び信仰の自由が受けられ、恐怖及び欠乏のない世界の到来が、一般の人々の最高の願望として宣言されたので、")
      payload.truncate_alert!

      payload.apns_hash["aps"]["alert"].should == "人権の無視及び軽侮が、人類の良心を踏みにじった野蛮行為をもたらし、言論及び信仰の自由が受けられ、恐怖及び欠乏のない世界の到来…"
      payload.apns_json.bytesize.should == 209
    end

    it "should complain if the trailing fill is too long" do
      payload = described_class.new(alert: long_alert)
      expect { payload.truncate_alert! long_alert }.to raise_error
    end

    it "should complain if the rest of the payload is too large" do
      payload = described_class.new(badge: 5, alert: "hmm", custom: {thing: long_alert})
      expect { payload.truncate_alert! }.to raise_error
    end

    it "should complain if there is no valid alert only if the payload is too large" do
      payload = described_class.new(badge: 5)
      expect { payload.truncate_alert! }.not_to raise_error

      payload = described_class.new(badge: 5, custom: {thing: long_alert})
      expect { payload.truncate_alert! }.to raise_error
    end

  end

end
