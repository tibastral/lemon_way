require 'spec_helper'

describe LemonWay::Client::WhiteLabel do
  before  do
    @base_uri = "http://api.lemonway.com"

    @default_params = {
        wlLogin: "test",
        wlPass: "test",
        wlPDV: "test",
        language: "fr",
        version: "1.0",
        channel: "W",
        walletIp: "91.222.286.32"
    }

    subject.init @default_params.merge(:base_uri => @base_uri)
    subject.rspec_reset
    #subject.unstub!
    WebMock.reset!
  end
  context "init" do
    it "should accept underscored keys" do
      params = @default_params.dup
      params.delete(:wlLogin)
      params[:wl_login] = "test"
      subject.init params.merge(:base_uri => @base_uri)
      subject.default_attributes.should have_key(:wlLogin)
    end
    it "should accept string keys" do
      subject.init @default_params.stringify_keys.merge(:base_uri => @base_uri)
      subject.default_attributes.should have_key(:wlLogin)
    end
  end

  context "LemonWay::Client::Base methods" do

    context "make_body" do
      before do
        @params = { wallet:          1 }
        @method_name = "tEst"
        @xml = subject.make_body(@method_name, @params)
      end

      it "should return an instructed xml string" do
        @xml.should be_a(String)
        @xml.should include("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      end

      it "should wrap attrs into a a tag method_name" do
        attrs = Hash.from_xml(@xml)
        attrs.should have_key(@method_name)

        @params.each do |k,v|
          attrs[@method_name].should have_key(k.to_s)
          attrs[@method_name][k.to_s].should eq(v)
        end
      end
    end
    context "define_query_method" do
      it "should add default_attributes to attrs arguments" do

      end
    end
    context "query" do
      it "should call method name and build body make_body" do
        method_name = "io"
        opts = {:a => 1}
        type = :post

        subject.should_receive(type).with( "/", :body => "xml").and_return({})
        subject.should_receive(:make_body).with(method_name, opts).and_return("xml")

        subject.query(type, method_name, opts)
      end

      it "should raise custom exception on error" do
        stub_request(:post, subject.base_uri).to_return :status => 400, :body => fixture_file("register_wallet_failure.xml")
        proc{
          subject.query(:post, "io")
        }.should raise_error(subject::Error)
      end

      it "should yield block if no exception" do
        stub_request(:post, subject.base_uri).to_return :status => 200, :body => fixture_file("register_wallet_success.xml")
        proc{
          subject.query(:post, "io") do |response|
            response.should be_a(ActiveSupport::HashWithIndifferentAccess)
          end
        }.should_not raise_error
      end

    end
    context "camelize_and_ensure_keys!"  do
      def camelize_and_ensure_keys!(attrs, required_attrs=[], optional_attrs=[])
        subject.camelize_and_ensure_keys! attrs.update(@default_params), required_attrs, optional_attrs
      end
      it "should raise error" do
        proc{
          camelize_and_ensure_keys!({:id => 1}, %i(id wallet))
          #subject.camelize_and_ensure_keys!()
        }.should raise_error(ArgumentError)
      end
      it "should raise error if an attribute has not a valid key" do
        proc{
          camelize_and_ensure_keys!({:id => 1, :walet => 2}, %i(id wallet))
          #subject.camelize_and_ensure_keys!(@default_params.merge(:id => 1, :walet => 2), %i(id wallet))
        }.should raise_error(ArgumentError)
      end
      it "should not raise error if all required attributes are present" do
        proc{
          camelize_and_ensure_keys!({:id => 1, :wallet => 2}, %i(id wallet))
        }.should_not raise_error
      end
      it "should raise error if an additional attribute is passed" do
        proc{
          camelize_and_ensure_keys!({:id => 1, :wallet => 2, :wid => 2}, %i(id wallet))
        }.should raise_error(ArgumentError)
      end
      it "should camelize_keys" do
        attrs = {:id => 1, :first_name => 2}
        proc{
          camelize_and_ensure_keys!(attrs, %i(id firstName))
          attrs.should have_key(:firstName)
        }.should_not raise_error
      end
    end
  end

  context "methods" do
    context "integration" do
      it "register_wallet" do
        params = {
            wallet:          1,
            client_mail:      "nicolas.papon@paymium.com",
            client_title:     "M",
            client_first_name: "nicolas",
            client_last_name:  "papon"
        }

        stub_request(:post, subject.base_uri).with do |request|
          attrs = Hash.from_xml(request.body)
          attrs.should have_key("RegisterWallet")
          params.merge(subject.default_attributes).each do |k,v|
            attrs["RegisterWallet"].should have_key(k.to_s)
            attrs["RegisterWallet"][k.to_s].should eq(v)
          end
        end.to_return :status => 200, :body => fixture_file("register_wallet_success.xml")
        wallet_id = subject.register_wallet params
        wallet_id.should == "12345"
      end
    end

    it "should respond to register_wallet" do
      subject.respond_to? :register_wallet
    end
    it "should respond to get_wallet_details" do
      subject.respond_to? :register_wallet
    end
    it "should respond to money_in" do
      subject.respond_to? :money_in
    end
    it "should respond to get_wallet_details" do
      subject.respond_to? :register_wallet
    end
    it "should respond to get_wallet_details" do
      subject.respond_to? :register_wallet
    end

  end

end