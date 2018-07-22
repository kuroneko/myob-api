require 'faraday'

module Myob
  module Api
    module Http
      class LocalConnection
        def initialize(options)
          @client = Faraday.new(options)
        end

        def get(url, options)
          @client.get(url) do |req|
            setup_request(req, options)
          end
        end

        def post(url, options)
          @client.post(url) do |req|
            setup_request(req, options)
          end
        end

        def put(url, options)
          @client.put(url) do |req|
            setup_request(req, options)
          end
        end

        private
        def setup_request(req, options)
          req.headers.merge!(options[:headers]) if options[:headers]
          req.params.merge!(options[:params]) if options[:params]
          req.body = options[:body] if options[:body]
        end
      end
    end
  end
end