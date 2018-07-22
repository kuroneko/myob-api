require 'base64'
require 'oauth2'

module Myob
  module Api
    class Client
      include Myob::Api::Helpers

      attr_reader :current_company_file, :client, :current_company_file_url

      # MYOB AccountRight API Client
      #
      # @param [Hash] options options to create the client with
      #   * :redirect_uri (String)
      #   * :consumer (Hash) API Consumer Key/Secret Tokens
      #     * :key (String) Consumer Key
      #     * :secret (String) Consumer Secret
      #   * :access_token (String) The OAuth Access token to use when connecting to AccountRight Live.
      #   * :refresh_token (String) The OAuth Refresh token to use when connecting to AccountRight Live.
      #   * :company_file (Hash) Details of the company file to connect to by default
      #     * :id (String) ID of the company file to connect to
      #     * :name (String) Name of the company file to connect to
      #     * :username (String) MYOB Username to use with the company file
      #     * :password (String) MYOB Password to use with the compahy file
      #   * :server_url (String) Base URL to a local AccountRight Server
      #
      # if :server_url is provided, then OAuth2 is disabled as suitable for use
      # with a local AccountRight server.
      def initialize(options)
        Myob::Api::Model::Base.subclasses.each {|c| model(c.name.split("::").last)}

        @redirect_uri         = options[:redirect_uri]
        @consumer             = options[:consumer]
        @access_token         = options[:access_token]
        @refresh_token        = options[:refresh_token]

        if options[:server_url]
          @client = Faraday.new()
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
      # `company_file` should be hash. accepted forms:
      #
      # {name: String, username: String, password: String}
      # {id: String, token: String}
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
            token = Base64.encode64("#{company_file[:username]}:#{company_file[:password]}")
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

      def connection
        if @skip_oauth
          @client
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
