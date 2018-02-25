# Unit tests for the Testbeat rspec extension

# needs gem install
require 'webmock'
include WebMock::API

@nodeactual = ENV['NODE']
ENV['NODE'] = "testhost01"

describe "testbeat_rspec" do
  require_relative "../../lib/rspec/spec_helper.rb"

  before(:all) do

    stub_request(:get, "http://testhost01/").
      to_return(:status => 301, :body => "", :headers => {'Location' => 'https://testhost01/'})

    stub_request(:head, "http://testhost01/").
      to_return(:status => 301, :headers => {'Location' => 'https://testhost01/'})

    stub_request(:get, "http://testhost01/insecure-resource.html").
      to_return(:status => 200, :body => "<html><head><title>Test</title><body><h1>Page</h1></body></html>", :headers => {})

    stub_request(:get, "https://testhost01/insecure-resource.html").
      to_return(:status => 404, :headers => {})

    stub_request(:get, "https://testhost01/").
      to_return(:status => 301, :body => "", :headers => {'Location' => 'https://testhost01/some/start.html'})

    stub_request(:head, "https://testhost01/").
      to_return(:status => 301, :headers => {'Location' => 'https://testhost01/some/start.html'})

    stub_request(:get, "https://testhost01/some/start.html").
      to_return(:status => 200, :body => "<html><head><title>Test</title><body><h1>Start</h1></body></html>", :headers => {})

    stub_request(:post, "https://testhost01/write").
      to_return(:status => 302, :body => "", :headers => {'Location' => 'https://testhost01/write/done'})

  end

  after(:all) do
    ENV['NODE'] = @nodeactual
    WebMock.disable!
  end

  describe "GET /" do

    it "Should create a @testbeat variable" do
      expect(@testbeat).to be_truthy
      expect(@somethingelse).to_not be_truthy
    end

    it "should identify examples starting with 'GET '" do
      expect(@testbeat.rest?)
    end

    it "should produce a response object" do
      expect(@response).to be_truthy
    end

    it "should be https (\"encrypted channel\") by default" do
      expect(@response).to be_truthy
      #expect(@response.code).to be == 301 # webmock returns code as string, does Net::HTTP do so too?
      expect("" + @response.code).to be == "301"
      expect(@response['Location']).to be == 'https://testhost01/some/start.html'
      expect(@response['Otherheader']).to be_falsy
    end

  end

  describe "GET /", redirect: true do

    it "Should follow redirect when the redirect option is true" do
      expect(@response).to be_truthy
      expect("" + @response.code).to be == "200"
      expect(@response.body).to match(/<h1>Start<\/h1>/)
    end

  end

  describe "HEAD /" do

    it "Makes response body empty" do
      expect(@response.body).to be_falsy
    end

    it "Gets response headers" do
      expect(@response['Location']).to be == 'https://testhost01/some/start.html'
    end

    describe "unencrypted" do

      it "Supports the same context shifts as GET" do
        expect(@response['Location']).to be == 'https://testhost01/'
      end

      it "Is a flag on @testbeat context" do
        expect(@testbeat.unencrypted?).to be true
      end

      it "Enforces unauthenticated" do
        expect(@testbeat.unauthenticated?).to be true
      end

    end

  end

  describe "POST /write",
      form: {
        name: 'a value'
      },
      headers: {
        Accept: 'application/json'
      } do

    #xit "Doesn't require a 'form:' arg"

    it "Sends the form" do
      assert_requested :post, "https://testhost01/write", :times => 1, :body => "name=a+value", headers: {Accept: 'application/json'}
    end

    it "Does not understand redirect-after-post by default" do
      expect(@response.code).to be == '302'
      expect(@response['Location']).to be == 'https://testhost01/write/done'
    end

  end

  describe "POST /write", body: "Some string" do

    it "POSTs a string body" do
      assert_requested :post, "https://testhost01/write", :times => 1, :body => "Some string"
    end

  end

  rcount = 0

  describe "GET /some/start.html", headers: { Accept: 'text/html' } do

    it "Produces a response body" do
      expect(@response.body).to match(/<h1>Start<\/h1>/)
      assert_requested :get, "https://testhost01/some/start.html", :times => rcount += 1
    end

    it "Runs the request once per describe" do
      expect(@response.body).to match(/<h1>Start<\/h1>/)
      assert_requested :get, "https://testhost01/some/start.html", :times => rcount
    end

    it "Supports custom request headers through the optional headers hash" do
      assert_requested :get, "https://testhost01/some/start.html", :headers => {'Accept' => 'text/html'}
    end

  end

  describe "GET /some/start.html" do

    describe "Request run 1" do

      it "Requests once for each sub-describe" do
        expect(@response.body).to match(/<h1>Start<\/h1>/)
        assert_requested :get, "https://testhost01/some/start.html", :times => rcount += 1
      end

      it "... so not here" do
        assert_requested :get, "https://testhost01/some/start.html", :times => rcount
        expect(@response.body).to match(/<h1>Start<\/h1>/)
      end

    end

    describe "Request run 2" do

      it "Requests once for each sub-describe" do
        expect(@response.body).to match(/<h1>Start<\/h1>/)
        assert_requested :get, "https://testhost01/some/start.html", :times => rcount += 1
      end

      it "... so not here" do
        assert_requested :get, "https://testhost01/some/start.html", :times => rcount
        expect(@response.body).to match(/<h1>Start<\/h1>/)
      end

    end

  end

  describe "unencrypted" do

    describe "GET /" do

      it "should do http requests in 'unencrypted' context" do
        expect(@response).to be_truthy
        #expect(@response.code).to be == 301 # webmock returns code as string, does Net::HTTP do so too?
        expect("" + @response.code).to be == "301"
        expect(@response['Location']).to be == 'https://testhost01/'
      end

    end

  end

  describe "GET /protected" do

    before(:all) do

      WebMock.reset!

      stub_request(:get, "https://testuser:testpassword@testhost01/protected").
        to_return(:status => 200)

      stub_request(:get, "https://testhost01/protected").
        to_return(:status => 401, :headers => { 'WWW-Authenticate' => 'Basic realm="Some realm"' })

    end

    it "Should first request without auth" do
      assert_requested :get, "https://testhost01/protected", :times => 1
    end

    it "The spec will never see the 401" do
      expect(@response.code).to be == "200"
    end

    it "Should then retry with testuser" do
      expect(@response.code).to be == "200"
      assert_requested :get, "https://testuser:testpassword@testhost01/protected", :times => 1
    end

    describe "unauthenticated" do

      it "Should give up on the 401" do
        expect(@response.code).to be == "401"
      end

    end

  end

  describe "GET /customport", port: 12345 do

    before(:all) do

      WebMock.reset!

      stub_request(:get, "http://testhost01:12345/customport").
        to_return(:status => 200, :body => "on custom port")

      stub_request(:get, "https://testhost01:12345/customport").
        to_return(:status => 200, :body => "on https custom port")

    end

    it "Should switch port for that particular request" do
      expect(@response.body).to match(/on https custom port/)
    end

    describe "unencrypted" do

      it "Should use the same custom port still" do
        expect(@response.body).to match(/on custom port/)
      end

    end

  end

  describe "Shell integration" do

    it "Exposes a 'shell' object that supports exec" do
      expect(@node.shell).to be_truthy
      expect(defined? @node.shell.exec).to be_truthy
    end

    it "Stub shell exposes a 'hasrun' array that logs attempts" do
      shell = @node.shell
      shell.exec('echo "test"')
      expect(shell.hasrun).to be_truthy
      expect(shell.hasrun[0]).to eq('echo "test"')
    end

  end

  describe "Misc context combinations" do

    gothost = nil

    before(:all) do
      gothost = @node.host
    end

    it "Sees node information immediately in context where spec_helper is require'd" do
      expect(gothost).to be_truthy
    end

  end

  describe "Verbose logging" do

    it "Writes to: testbeat-debug.log" do
      expect(File::exist? 'testbeat-debug.log').to be true
    end

  end

end
