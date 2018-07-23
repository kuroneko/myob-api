require 'base64'
require 'oauth2'

module Myob
  module Api
    # Myob::Api::Client provides an interface to query data from MYOB
    # AccountRight Live or an MYOB AccountRight API server instance.
    #
    # Data can be fetched using the {Myob::Api::Model::Base} subclasses, each of
    # which has a accessor underneath this class which can be used to get or
    # send updates to the API.  These are automatically mapped using the
    # underscored versions of the last segment of their class names.
    # (ie:  {Myob::Api::Model::CompanyFile} becomes +#company_file+)
    class Client
      include Myob::Api::Helpers

      # @return [Hash] Returns options for the current company file as set/interpreted by {#select_company_file}
      attr_reader :current_company_file

      # @api private
      # @return the internal client used to access the API
      attr_reader :client

      # @return [String] The base URI for the bound company file, if set by {#select_company_file}, +nil+ otherwise
      attr_reader :current_company_file_url

      DEFAULT_API_URL = 'https://api.myob.com/accountright/'

      # Initialize a new instance of a API Client.
      #
      # if +:server_url+ is provided, then OAuth2 is disabled as suitable for
      # use with a local AccountRight API server.
      #
      # @option options [String] redirect_uri
      # @option options [String] consumer_key MYOB AccountRight Live Consumer Key
      # @option options [String] consumer_secret MYOB AccountRight Live Consumer Secret
      # @option options [String] access_token OAuth2 Access Token
      # @option options [String] refresh_token OAuth2 Refresh Token
      # @option options [Hash] company_file Details of the default company file to open.  Same options as used by {#select_company_file}.
      # @option options [String] server_url Base URL for an AccountRight API Server (not AccountRight Live) #
      def initialize(options)
        Myob::Api::Model::Base.subclasses.each {|c| model(c.name.split("::").last)}

        @redirect_uri         = options[:redirect_uri]
        @consumer             = {
          key:    options[:consumer_key] || nil,
          secret: options[:consumer_secret] || nil,
        }
        @access_token         = options[:access_token]
        @refresh_token        = options[:refresh_token]
        @api_url              = options[:server_url]

        if @api_url
          @client = nil
          @skip_oauth = true
        else
          @client               = OAuth2::Client.new(@consumer[:key], @consumer[:secret], {
            :site          => 'https://secure.myob.com',
            :authorize_url => '/oauth2/account/authorize',
            :token_url     => '/oauth2/v1/authorize',
          })
          @skip_oauth = false
        end
        # on client init, if we have a company file already, get the appropriate base URL for this company file from MYOB
        provided_company_file = options[:selected_company_file] || options[:company_file]
        select_company_file(provided_company_file) if provided_company_file
        @current_company_file ||= {}
      end

      # returns the configured Base URL.  (Only used for Company File lookups,
      # as the results from that lookup contains the full base URI for the
      # company_file)
      #
      # @return [String] The Base URL for the service (typically the company file endpoint)
      def api_url
        @api_url || DEFAULT_API_URL
      end

      def get_access_code_url(params = {})
        @client.auth_code.authorize_url(params.merge(scope: 'CompanyFile', redirect_uri: @redirect_uri))
      end

      def get_access_token(access_code)
        @token         = @client.auth_code.get_token(access_code, redirect_uri: @redirect_uri)
        @access_token  = @token.token
        @expires_at    = @token.expires_at
        @refresh_token = @token.refresh_token
        @token
      end

      # Returns the set of headers to use on a request to this API server.
      #
      # @api private
      def headers
        headerRet = {
          'x-myobapi-version' => 'v2',
          'Content-Type'      => 'application/json'
        }
        token = (@current_company_file || {})[:token]
        unless token.nil? || token.empty?
          headerRet['x-myobapi-cftoken'] = token
        end
        key = (@consumer || {})[:key]
        unless key.nil? || key.empty?
          headerRet['x-myobapi-key'] = key
        end
        headerRet
      end

      # given some company file credentials, connect to MYOB and get the appropriate company file object.
      # store its ID and token for auth'ing requests, and its URL to ensure we talk to the right MYOB server.
      #
      # A valid specification should contain both of:
      # * Either a correctly encoded authentication token, or a username and password pair.
      # * Either the company file name, or its ID.
      #
      # A list of known company files can be obtained using {Model::CompanyFile}
      #
      # @option company_file [String] name A complete company file name to match against
      # @option company_file [String] id A company file GUID to match against
      # @option company_file [String] username The user to access the company file as
      # @option company_file [String] password The password to access the company file with
      # @option company_file [String] token An pre-encoded authentication token as used by the AccountRight API
      #
      # @return [void]
      def select_company_file(company_file)
        # store the provided company file as an ivar so we can use it for subsequent requests
        # we need the token from it to make the initial request to get company files
        @current_company_file ||= company_file if company_file[:token]

        selected_company_file = company_files.find {|file|
          if company_file[:name]
            file['Name'] == company_file[:name]
          elsif company_file[:id]
            file['Id'] == company_file[:id]
          end
        }

        if selected_company_file
          token = company_file[:token]
          if (token.nil? || token == '') && !company_file[:username].nil? && company_file[:username] != '' && !company_file[:password].nil?
            # if we have been given login details, encode them into a token
            token = Base64.encode64("#{company_file[:username]}:#{company_file[:password]}").chomp
          end
          @current_company_file = {
            :id    => selected_company_file['Id'],
            :token => token
          }
          @current_company_file_url = selected_company_file['Uri']
        else
          @current_company_file = {}
        end
      end

      # @return [Http::LocalConnection,OAuth2::Client] Gets a connection object
      #   to talk to the API.
      # @api private
      def connection
        if @skip_oauth
          @local_connection ||= Myob::Api::Http::LocalConnection.new(url: api_url)
        else
          if @refresh_token
            @auth_connection ||= OAuth2::AccessToken.new(@client, @access_token, {
              :refresh_token => @refresh_token
            }).refresh!
          else
            @auth_connection ||= OAuth2::AccessToken.new(@client, @access_token)
          end
        end
      end

      private
      def company_files
        @company_files ||= self.company_file.all.to_a
      end
    end
  end
end
