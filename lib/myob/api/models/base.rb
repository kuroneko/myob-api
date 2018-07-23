require 'objspace'

module Myob
  module Api
    module Model
      # Base provides the fundamental behaviour required to query AccountRight
      # for a specific type of data.
      #
      # In general, objects that return paginated data will return a hash with
      # element +"Items"+ which contains the array of objects returned.
      #
      # The objects themselves are simply the hashified JSON objects returned
      # by the API - they are not wrapped in this class.
      #
      # @abstract Subclass and implement {#model_route} to implement a new MYOB
      #   AccountRight API object type, then require the class in +myob-api.rb+
      #   before +myob/api/client+ is required.
      class Base
        QUERY_OPTIONS = [:orderby, :top, :skip, :filter]

        def initialize(client, model_name)
          @client          = client
          @model_name      = model_name || 'Base'
          @next_page_link  = nil
        end

        # model_route returns the path of the object it represents below the
        # CompanyFile ID.
        #
        # i.e: Customer maps to 'Contact/Customer'
        #
        # @return string
        def model_route
          @model_name.to_s
        end

        # Queries the API for the first page of objects.
        #
        # Once called, {#next_page?} can be used to verify if there are further
        # pages of objects to retrieve, and {#next_page} can be used to retrieve
        # that next page.
        #
        # @return [Hash] A hash containing the data (see the Class description)
        def all(params = nil)
          perform_request(self.url(nil, params))
        end
        alias_method :get, :all

        # Queries the API ala {#all}, but unwraps down to the +"Items"+ element
        # if it is present
        #
        # @note This method seems ill-conceived and probably shouldn't be used.
        #
        # @return [Object] Either the JSON object returned, or the object or array in the +"Items"+ slot if JSON object had one.
        def records(params = nil)
          response = all(params)
          response.is_a?(Hash) && response.key?('Items') ? response['Items'] : response
        end

        # @return [boolean] +true+ if the last query indicated there were more objects to load, +false+ otherwise
        def next_page?
          !!@next_page_link
        end

        # Returns the next page of data from the last fetch performed.
        #
        # @return [Hash] A hash containing the data (see the Class description)
        def next_page(params = nil)
          perform_request(@next_page_link)
        end

        def all_items(params = nil)
          results = all(params)["Items"]
          while next_page?
            results += next_page["Items"] || []
          end
          results
        end
        
        def find(id)
          object = { 'UID' => id }
          perform_request(self.url(object))
        end
        
        def first(params = nil)
          all(params).first
        end

        # Save the object provided to AccountRight, either creating if it is new,
        # or updating it otherwise.
        #
        # @param object [Hash] The AccountRight Object to save
        def save(object)
          new_record?(object) ? create(object) : update(object)
        end

        def destroy(object)
          @client.connection.delete(self.url(object), :headers => @client.headers)
        end

        def url(object = nil, params = nil)
          url = if self.model_route == ''
            @client.api_url
          else
            if @client && @client.current_company_file_url
              "#{@client.current_company_file_url}/#{self.model_route}#{"/#{object['UID']}" if object && object['UID']}"
            else
              "#{@client.api_url}#{@client.current_company_file[:id]}/#{self.model_route}#{"/#{object['UID']}" if object && object['UID']}"
            end
          end

          if params.is_a?(Hash)
            query = query_string(params)
            url += "?#{query}" if !query.nil? && query.length > 0
          end

          url
        end

        # This method checks to see if the object has been previously persisted.
        #
        # @param object [Hash] The AccountRight Object to check
        # @return [boolean] true if the object is new, false if the object has been previously saved
        def new_record?(object)
          object["UID"].nil? || object["UID"] == ""
        end

        # @private
        # @api private
        # @note copied from active_support so we don't need to pull in all of
        #   active_support just to use the MYOB API.
        def self.descendants
          descendants = []
          ObjectSpace.each_object(singleton_class) do |k|
            next if k.singleton_class?
            descendants.unshift k unless k == self
          end
          descendants
        end

        # @private
        # @api private
        # @note copied from active_support so we don't need to pull in all of
        #   active_support just to use the MYOB API.
        def self.subclasses
          subclasses, chain = [], descendants
          chain.each do |k|
            subclasses << k unless chain.any? { |c| c > k }
          end
          subclasses
        end

        private
        def create(object)
          object = typecast(object)
          response = @client.connection.post(self.url, {:headers => @client.headers, :body => object.to_json})
        end

        def update(object)
          object = typecast(object)
          response = @client.connection.put(self.url(object), {:headers => @client.headers, :body => object.to_json})
        end

        def typecast(object)
          returned_object = object.dup # don't change the original object

          returned_object.each do |key, value|
            if value.respond_to?(:strftime)
              returned_object[key] = value.strftime(date_formatter)
            end
          end

          returned_object
        end

        def date_formatter
          "%Y-%m-%dT%H:%M:%S"
        end
        
        def resource_url
          if @client && @client.current_company_file_url
            "#{@client.current_company_file_url}/#{self.model_route}"
          else
            "#{@client.api_url}#{@client.current_company_file[:id]}/#{self.model_route}"
          end
        end
        
        def perform_request(url)
          model_data = parse_response(@client.connection.get(url, {:headers => @client.headers}))
          @next_page_link = model_data['NextPageLink'] if self.model_route != ''
          model_data
        end

        def query_string(params)
          params.map do |key, value|
            if QUERY_OPTIONS.include?(key)
              value = build_filter(value) if key == :filter
              key = "$#{key}"
            end

            "#{key}=#{CGI.escape(value.to_s)}"
          end.join('&')
        end

        def build_filter(value)
          return value unless value.is_a?(Hash)

          value.map { |key, value| "#{key} eq '#{value.to_s.gsub("'", %q(\\\'))}'" }.join(' and ')
        end

        def parse_response(response)
          JSON.parse(response.body)
        end

        def process_query(data, query)
          query.each do |property, value|
            data.select! {|x| x[property] == value}
          end
          data
        end

      end
    end
  end
end
