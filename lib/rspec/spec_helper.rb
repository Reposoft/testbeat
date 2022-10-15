
require "awesome_print"
require "resolv-replace"
require "net/http"
require "openssl"
require "json"
require "hashie"
require "logger"

# TODO can we support http://www.relishapp.com/rspec/rspec-core/v/3-1/docs/example-groups/shared-context

# Node should have getters for repository and hosting specifics
# Configuration attributes for the node should are available as [:properties]

# global so we don't need to pass this around to utility classes
$logger = Logger.new('testbeat-debug.log')

HTTP_VERBS = {
  'COPY'      => Net::HTTP::Copy,
  'DELETE'    => Net::HTTP::Delete,
  'GET'       => Net::HTTP::Get,
  'HEAD'      => Net::HTTP::Head,
  'LOCK'      => Net::HTTP::Lock,
  'MKCOL'     => Net::HTTP::Mkcol,
  'MOVE'      => Net::HTTP::Move,
  'OPTIONS'   => Net::HTTP::Options,
  'PATCH'     => Net::HTTP::Patch,
  'POST'      => Net::HTTP::Post,
  'PROPFIND'  => Net::HTTP::Propfind,
  'PROPPATCH' => Net::HTTP::Proppatch,
  'PUT'       => Net::HTTP::Put,
  'TRACE'     => Net::HTTP::Trace,
  'UNLOCK'    => Net::HTTP::Unlock
}

HTTP_VERB_RESOURCE = /^(COPY|DELETE|GET|HEAD|LOCK|MKCOL|MOVE|OPTIONS|PATCH|POST|PROPFIND|PROPPATCH|PUT|TRACE|UNLOCK)\s+(\S+)/

class TestbeatNode

  def initialize(nodename)
    @name = nodename
    if !@name || @name.length == 0
      logger.error { "Node name not set, at #{Dir.pwd}" }
      raise "Node name not set"
    end
    hostsFile = "#{folder}/hosts_custom"
    if File.exists?(hostsFile)
      hosts_resolver = Resolv::Hosts.new(hostsFile)
      dns_resolver = Resolv::DNS.new
      Resolv::DefaultResolver.replace_resolvers([hosts_resolver, dns_resolver])
      logger.info { "Custom DNS for #{nodename} from #{hostsFile}" }
      # TODO: Remove puts when stable.
      puts "Custom DNS for #{nodename} from #{hostsFile}"
    else
      logger.warn { "Failed to locate custom hosts file, from #{hostsFile}, at #{Dir.pwd}" }
      puts "Failed to locate custom hosts file, from #{hostsFile}, at #{Dir.pwd}"
    end
    attributesFile = "#{folder}/chef.json"
    if File.exists?(attributesFile)
      @attributes = read_chef_attributes(attributesFile)
    else
      logger.warn { "Failed to locate node attributes, from #{attributesFile}, at #{Dir.pwd}" }
      @attributes = nil
    end
    logger.info { "Node initialized #{nodename}, attributes from #{attributesFile}" }
  end

  def logger
    $logger
  end

  def folder
    "nodes/#{@name}"
  end

  def vagrant?
    vagrantfile = "#{folder}/Vagrantfile"
    return File.exists?(vagrantfile)
  end

  # Attributes defined specifically on the node, not aggregated like in chef runs
  def attributes
    @attributes
  end

  def attributes?
    @attributes != nil
  end

  # Provides access to attributes, if available, as @node[key] much like in chef cookbooks
  # Use .keys to see if a key exists
  def [](key)
    return nil if @attributes == nil
    # Raise exception so test issues are clearly displayed in rspec output (puts is displayed before test output, difficult to identify which test it comes from)
    raise "Missing attribute key '#{key}', got #{@attributes.keys}" if not @attributes.key?(key)
    @attributes[key]
  end

  # More methods to work like hash
  def keys
    @attributes.keys
  end

  def key?(key)
    @attributes.key?(key)
  end

  # host is assumed to be equivalent with node name now, but we could read it from attributes, see ticket:1017
  def host
    @name
  end

  # returns hash "username" and "password", or false if unsupported
  def testauth
    return false # we don't support authenticated nodes yet
  end

  # return command line access, instance of TestbeatNodeRsh, or false if unsupported
  # This is probably easier to support than get_bats; on vagrant nodes we have 'vagrant ssh -c'
  def shell
    if not vagrant?
      return TestbeatShellStub.new()
    end
    return TestbeatShellVagrant.new(folder)
  end

  def provision
    if not vagrant?
      raise "Provision support will probably require a vagrant box"
    else
      raise "Provision not implemented"
    end
  end


  def to_s
    "Testbeat node #{@name}"
    #ap @attributes
  end

  # The following methods are private
  private

  # Returns node attributes from node file compatible with "knife node from file"
  # Returns as Mash because that's what chef uses
  def read_chef_attributes(jsonPath)
    #p "read attributes from #{jsonPath}"
    data = nil
    File::open(jsonPath) { |f|
      data = f.read
    }
    raise "Failed to read file #{jsonPath}" if data == nil
    json = JSON.parse(data)
    mash = Hashie::Mash.new(json)
    raise "Missing 'normal' attributes in node file #{jsonPath}" if not mash.key?("normal")
    return mash["normal"]
  end

end

# Support different types of command execution on node
class TestbeatShell

  def exec(cmd)
    raise "Command execution on this node is not supported"
  end

end

class TestbeatShellVagrant

  def initialize(vagrantFolder)
    @vagrantFolder = vagrantFolder
  end

  def exec(cmd)
    $logger.debug {"Exec: #{cmd}"}
    stdout = nil
    Dir.chdir(@vagrantFolder){
      @out = %x[vagrant ssh -c '#{cmd}' 2>&1]
      @status = $?
    }
    $logger.debug {"Exec result #{exitstatus}: #{@out[0,50].strip}"}
    return self
  end

  # output of latest exec (stdout and stderr merged, as we haven't worked on separating them)
  def out
    @out
  end

  def exitstatus
    @status.exitstatus
  end

  def ok?
    exitstatus == 0
  end

end

class TestbeatShellStub

  def initialize()
    @hasrun = Array.new
  end

  def hasrun
    @hasrun
  end

  def exec(cmd)
    @hasrun.push(cmd)
    $logger.warn "No guest shell available to exec: '#{cmd}'"
  end

  def out
    "(No guest shell for current testbeat context)"
  end

  def exitstatus
    @hasrun.length
  end

  def ok?
    false
  end
end

# Context has getters for test case parameters that can be digged out from Rspec examples,
# initialized for each "it"
class TestbeatContext

  # reads context from RSpec example metadata
  def initialize(example)
    # enables de-duplication of requests within describe, using tostring to compare becase == wouldn't work
    @context_block_id = "#{example.metadata[:example_group][:block]}"

    # defaults
    if ENV.key?( 'TESTBEAT_SESSION' )
      @session = ENV['TESTBEAT_SESSION']
    else
      @user = { :username => 'testuser', :password => 'testpassword' }
    end
    @unencrypted = false
    @unauthenticated = false
    @rest = false
    @reprovision = false

    # actual context
    parse_example_group(example.metadata[:example_group], 0)

    @context_block_id_short = /([^\/]+)>$/.match(@context_block_id)[1]
    logger.info{ "#{example.metadata[:example_group][:location]}: #{@rest ? @method : ''} #{@resource} #{@unencrypted ? '[unencrypted] ' : ' '}#{@unauthenticated ? '[unauthenticated] ' : ' '}" }
  end

  def logger
    $logger
  end

  def context_block_id
    @context_block_id
  end

  # Returns true if the current context has a REST request specified
  def rest?
    @rest
  end

  def nop?
    !rest?
  end

  def user
    @user
  end

  def session
    @session
  end

  # Returns the REST resource if specified in context
  def resource
    if not rest?
      return nil
    end
    @resource
  end

  def method
    if not rest?
      return nil
    end
    @method
  end

  def redirect
    @rest_redirect
  end

  def redirect?
    !!redirect
  end

  def port
    @rest_port
  end

  def port?
    !!port
  end

  def headers
    @rest_headers
  end

  def headers?
    !!headers
  end

  def body
    @rest_body
  end

  def body?
    !!body
  end

  def form
    @rest_form
  end

  def form?
    !!form
  end

  # Returns true if requests will be made without authentication even if the node expects authentication
  def unauthenticated?
    unencrypted? || @unauthenticated
  end

  def unencrypted?
    @unencrypted
  end

  def reprovision?
    @reprovision
  end

  def to_s
    s = "Testbeat context"
    if rest?
      s += " #{method} #{resource}"
    else
      s += " non-REST"
    end
    if @unencrypted
      s += " unencrypted"
    elsif @unauthenticated
      s += " unauthenticated"
    end
    s
  end

  private

  def parse_example_group(example_group, uplevel)
    if example_group[:parent_example_group]
      parse_example_group(example_group[:parent_example_group], uplevel + 1)
    end
    logger.debug{ "Parsing context #{uplevel > 0 ? '-' : ' '}#{uplevel}: #{example_group[:description]}" }
    parse_description_args(example_group[:description_args])
    if rest?
      if example_group[:body]
        @rest_body = example_group[:body]
      end
      if example_group[:form]
        @rest_form = example_group[:form]
      end
      if example_group[:headers]
        @rest_headers = example_group[:headers]
      end
      if example_group[:port]
        @rest_port = example_group[:port]
      end
      if example_group[:redirect]
        @rest_redirect = example_group[:redirect]
      end
    end

  end

  def parse_description_args(example_group_description_args)
    a = example_group_description_args[0]

    /unencrypted/i.match(a) {
      @unencrypted = true
    }

    /unauthenticated/i.match(a) {
      @unauthenticated = true
    }

    HTTP_VERB_RESOURCE.match(a) { |rest|
      @rest = true
      @method = rest[1]
      @resource = rest[2]
    }

    /reprovision/i.match(a) {
      @reprovision = true
    }

    # idea: nodes that should not be modified (production etc), particularily not through shell
    #/untouchable/
  end

end

$_testbeat_rest_reuse = Hash.new

class TestbeatRestRequest

  def initialize(node, testbeat)
    #@headers = {}
    @timeout = 10
    @node = node # TestbeatNode
    @testbeat = testbeat #TestbeatContext
  end

  # Initiate the request and return Net::HTTPResponse object,
  # supporting response [:responseHeaderName], .body (string), .code (int), .msg (string)
  def run
    reuse_id = @testbeat.context_block_id
    previous = $_testbeat_rest_reuse[reuse_id]
    if previous
      @response = previous
      @testbeat.logger.info{ "Request reused within #{reuse_id} responded #{@response.code} #{@response.message}" }
      return @response
    end
    # If there's no built in auth support in Net::HTTP we can check for 401 here and re-run the request with auth header
    Net::HTTP.start(@node.host,
      @testbeat.port,
      :use_ssl => !@testbeat.unencrypted?,
      :verify_mode => OpenSSL::SSL::VERIFY_NONE,  # Ideally verify should be enabled for non-labs hosts (anything with a FQDN including dots)
      :open_timeout => @timeout,
      :read_timeout => @timeout
      ) do |http|

      if not HTTP_VERBS.has_key?(@testbeat.method)
        raise "Testbeat can't find HTTP verb #{@testbeat.method}"
      end

      req = HTTP_VERBS[@testbeat.method].new(@testbeat.resource)
      if @testbeat.session and not @testbeat.unauthenticated?
        @testbeat.logger.info{ "Authenticating to #{@testbeat.resource} with #{@testbeat.session}" }
        #puts "Authenticating to #{@testbeat.resource} with #{@testbeat.session}"
        req['Cookie'] = @testbeat.session
      end
      if @testbeat.user and not @testbeat.unauthenticated?
        # Now using forced Basic Auth. Test the realm by using 'unauthenticated'.
        u = @testbeat.user
        @testbeat.logger.info{ "Authenticating to #{@testbeat.resource} with #{u[:username]}:#{u[:password]}" }
        req.basic_auth u[:username], u[:password]
      end
      if @testbeat.headers?
        @testbeat.headers.each {|name, value| req[name] = value }
      end
      if @testbeat.form?
        if not req.methods.include? :set_form_data
          raise "Testbeat can't set form data for HTTP verb #{@testbeat.method}"
        end
        req.set_form_data(@testbeat.form)
      end
      if @testbeat.body?
        if not req.request_body_permitted?
          raise "Testbeat can't set body for HTTP verb #{@testbeat.method}"
        end
        req.body = @testbeat.body
      end

      @response = http.request(req) # Net::HTTPResponse object

      # The redirect must not be authenticated. Consider copying 401 handling to above redirect handling.
      # Follows a single redirect, no recursive redirects (a feature in a test framework).
      if (@response.code == "301" or @response.code == "302") and @testbeat.redirect
        @testbeat.logger.info{ "Redirecting #{@response.code} to #{@response['location']}" }
        redirectTo = URI.parse(@response['location'])
        redirectToPath = [redirectTo.path,redirectTo.query].join('?')
        #reqRedirect = req.new(redirectTo.path, req.to_hash()) # new(path, initheader = nil)
        reqRedirect = HTTP_VERBS[@testbeat.method].new(redirectToPath) # new(path, initheader = nil)
        if @testbeat.session and not @testbeat.unauthenticated?
          @testbeat.logger.info{ "Authenticating to #{@testbeat.resource} with #{@testbeat.session}" }
          #puts "Authenticating redirect to #{@testbeat.resource} with #{@testbeat.session}"
          reqRedirect['Cookie'] = @testbeat.session
        end
        if @testbeat.headers?
          @testbeat.headers.each {|name, value| reqRedirect[name] = value }
        end
        reqRedirect.body = req.body
        @response = http.request(reqRedirect)
        req = reqRedirect # Needed by auth support below.
        @testbeat.logger.info{ "Redirected #{@response.code}" }
      end

      @testbeat.logger.info{ "Request #{@testbeat.resource} responded #{@response.code} #{@response.message}" }
      $_testbeat_rest_reuse[reuse_id] = @response
      return @response
    end
  end

end

RSpec.configure do |config|

  activenodes = {}

  # We can't use before(:suite) because it does not support instance variables
  config.before(:context) do |context|

    nodearg = ENV['NODE']
    next if nodearg.nil?

    if not activenodes.has_key?(nodearg)
      activenodes[nodearg] = TestbeatNode.new(nodearg)
    end
    @node = activenodes[nodearg]

  end

  # https://www.relishapp.com/rspec/rspec-core/docs/hooks/before-and-after-hooks
  config.before(:example) do |example|
    #puts "------------- before"
    #ap example.metadata
    #ap example.metadata[:description_args]
    #ap example[:description_args]
    #ap example.full_description

    # Testbeat can do nothing without a node, so the example will continue as a regular Rspec test
    next if not @node

    @testbeat = TestbeatContext.new(example)

    # If there's no REST call in the example we're happy just to define @testbeat with access to command line etc
    next if @testbeat.nop?

    if @testbeat.unencrypted? and @testbeat.unauthenticated?
      # Nodes that require non-test authentication are currently out of scope for the test framework
      # This means we must skip specs in an "unauthenticated" context, or let them fail, because we won't get the 401 responses we'd expect
      #p "--- Should be skipped; nodes that require authentication are currently unsupported"
    elsif @testbeat.unencrypted?
      # When we do add support for authentication to nodes, there should be no authentication on insecure channel
    elsif @testbeat.reprovision?
      # We have to run a new provisioning. For repos-backup amongst others.
      @testbeat.logger{ "Reprovision triggered" }
      @node.provision
    else
      # Authenticated is default, meaning that specs should be written with the assumption that all services are accessible
    end

    if @testbeat.rest?
      @testbeat.logger{ "Request triggered" }
      req = TestbeatRestRequest.new(@node, @testbeat)
      begin
        @response = req.run
      rescue OpenSSL::SSL::SSLError => e
        @response = { :error => e }
      end
    end

    #p "Got reponse code #{@response.code}"
    #ap @response.header.to_hash
  end

  config.after(:example) do
    #puts "------------- after"
  end
end
