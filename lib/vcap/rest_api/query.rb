require 'time'

module VCAP::RestAPI
  #
  # Query against a model using a query string received via http query
  # parameters.
  #
  # Note: we use both a model and a dataset because we need to know properties
  # about the model.  We also want to query against a potentially already
  # filtered dataset.  Since datasets aren't bound to a particular model,
  # we need to pass both pieces of infomration.
  class Query
    # Create a new Query.
    #
    # @param [Sequel::Model] model The model to query against
    #
    # @param [Sequel::Dataset] ds The dataset to query against
    #
    # @param [Set] queryable_attributes The attributes allowed to be used as
    # keys in a query.
    #
    # @param [Hash] query_params A hash containing the full set of http
    # query parameters.  Currently, only :q is extracted and used as the query
    # string.  The :q entry is a key value pair of the form 'key:value'
    def initialize(model, ds, queryable_attributes, query_params)
      @model = model
      @ds = ds
      @queryable_attributes = queryable_attributes
      @query = Array(query_params[:q])
    end

    # Return the dataset associated with the query.  Note that this does not
    # result in fetching records from the db.
    #
    # @return [Sequel::Dataset]
    def filtered_dataset
      filter_args_from_query.inject(@ds) do |filter, cond|
        filter.filter(cond)
      end
    end

    # Return the dataset for the supplied query.
    # Note that this does not result in fetching records from the db.
    #
    # @param [Sequel::Model] model The model to query against
    #
    # @param [Sequel::Dataset] ds The dataset to query against
    #
    # @param [Set] queryable_attributes The attributes allowed to be used as
    # keys in a query.
    #
    # @param [Hash] query_params A hash containing the full set of http
    # query parameters.  Currently, only :q is extracted and used as the query
    # string.  The :q entry is a key value pair of the form 'key:value'
    #
    # @return [Sequel::Dataset]
    def self.filtered_dataset_from_query_params(model,
                                                ds,
                                                queryable_attributes,
                                                query_params)
      self.new(model, ds, queryable_attributes, query_params).filtered_dataset
    end

    private

    def filter_args_from_query
      return {} unless query

      parse.collect do |key, comparison, val|
        query_filter(key, comparison, val)
      end
    end

    class << self
      attr_accessor :uuid
    end

    def parse
      Query.uuid ||= SecureRandom.uuid
      segments = []

      query.each do |q|
        q.gsub!(';;', Query.uuid)
        segments.concat(q.split(';'))
      end

      segments.collect do |segment|
        segment.gsub!(Query.uuid, ';')
        key, comparison, value = segment.split(/(:|>=|<=|<|>| IN )/, 2)

        comparison = '=' if comparison == ':'

        unless queryable_attributes.include?(key)
          raise VCAP::Errors::ApiError.new_from_details('BadQueryParameter', key)
        end

        [key.to_sym, comparison, value]
      end
    end

    def query_filter(key, comparison, val)
      foreign_key_association = foreign_key_association(key)
      if comparison == ' IN '
        do_glob_check = false
        glob = false
        values = val.split(',')
      else
        do_glob_check = true
        values = [val]
      end

      return clean_up_foreign_key(key, values, foreign_key_association) if foreign_key_association
      col_type = column_type(key)
      if do_glob_check
        glob = [:string, :citext].include?(col_type) && val.match(/#{Regexp.escape('*')}$/)
      end

      col_type = column_type(key)
      values = values.collect { |value| cast_query_value(col_type, key, value) }.compact

      if values.empty?
        { key => nil }
      elsif glob
        ["#{key} LIKE ?", values]
      else
        ["#{key} #{comparison} ?", values]
      end
    end

    def query_filter__xx(key, comparison, val)
      oval = val
      col_type = column_type(key)
      foreign_key_association = foreign_key_association(key)
      if comparison == " IN "
        glob = false
        val = val.split(",").collect { |value| cast_query_value(col_type, key, value) }
        values = val
      else
        glob = [:string, :citext].include?(col_type) && val.match(/#{Regexp.escape('*')}$/)
        val = cast_query_value(col_type, key, val)
        values = [val]
      end

      return clean_up_foreign_key(key, values, foreign_key_association) if foreign_key_association

      col_type = column_type(key)
      values = values.collect{ |value| cast_query_value(col_type, key, value) }.compact

      if values.size == 0
        { key => nil }
      elsif glob
        ["#{key} LIKE ?", values]
      else
        ["#{key} #{comparison} ?", val]
      end
    end

    def cast_query_value(col_type, key, value)
      case col_type
      when :integer
        clean_up_integer(value)
      when :boolean
        clean_up_boolean(key, value)
      when :datetime
        clean_up_datetime(value)
      when :string, :citext
        clean_up_string(value)
      else
        value
      end
    end

    def foreign_key_association(query_key)
      return unless query_key =~ /(.*)_(gu)?id$/

      foreign_key_table = Regexp.last_match[1]

      if model.associations.include?(foreign_key_table.to_sym)
        foreign_key_table.to_sym
      elsif model.associations.include?(foreign_key_table.pluralize.to_sym)
        foreign_key_table.pluralize.to_sym
      end
    end

    def clean_up_foreign_key(query_key, query_values, foreign_key_column_name)
      raise_if_column_is_missing(query_key, foreign_key_column_name)

      other_model = model.association_reflection(foreign_key_column_name).associated_class
      id_key = other_model.columns.include?(:guid) ? :guid : :id
      foreign_key_value = other_model.filter(id_key => query_values)

      { foreign_key_column_name => foreign_key_value }
    end

    # Sequel uses tinyint(1) to store booleans in Mysql.
    # Mysql does not support using 't'/'f' for querying.
    def clean_up_boolean(_, q_val)
      q_val == 't' || q_val == 'true'
    end

    def clean_up_datetime(q_val)
      q_val.empty? ? nil : Time.parse(q_val).utc
    end

    def clean_up_integer(q_val)
      q_val.empty? ? nil : q_val.to_i
    end

    def clean_up_string(q_val)
      if q_val.match /#{Regexp.escape('*')}$/
        q_val.gsub(/\*$/, '%')
      else
        q_val
      end
    end

    def column_type(query_key)
      column = model.db_schema[query_key.to_sym]
      raise_if_column_is_missing(query_key, column)
      column[:type] || column[:db_type].to_sym
    end

    def raise_if_column_is_missing(query_key, column)
      # One could argue that this should be a server error.  It means
      # that a query key came in for an attribute that is explicitly
      # in the queryable_attributes, but is not a column or an association.

      raise VCAP::Errors::ApiError.new_from_details('BadQueryParameter', query_key) unless column
    end

    attr_accessor :model, :access_filter, :queryable_attributes, :query
  end
end
