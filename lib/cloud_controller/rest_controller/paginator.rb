require 'addressable/uri'

module VCAP::CloudController::RestController

  # Paginates a dataset
  class Paginator
    # Paginate and render a dataset to json.
    #
    # @param [RestController] controller Controller for the
    # dataset being paginated.
    #
    # @param [Sequel::Dataset] ds Dataset to paginate.
    #
    # @param [String] path Path used to fetch the dataset.
    #
    # @option opts [Integer] :page Page number to start at.  Defaults to 1.
    #
    # @option opts [Integer] :results_per_page Number of results to include
    # per page.  Defaults to 50.
    #
    # @option opts [Boolean] :pretty Controlls pretty formating of the encoded
    # json.  Defaults to true.
    #
    # @option opts [Integer] :inline_relations_depth Depth to recursively
    # exapend relationships in addition to providing the URLs.
    #
    # @option opts [Integer] :max_inline Maximum number of objects to
    # expand inline in a relationship.
    #
    # @return [String] Json encoding pagination of the dataset.
    def self.render_json(controller, ds, path, opts, request_params = {})
      self.new(controller, ds, path, opts, request_params).render_json
    end

    # Create a paginator.
    #
    # @param [RestController] controller Controller for the
    # dataset being paginated.
    #
    # @param [Sequel::Dataset] ds Dataset to paginate.
    #
    # @param [String] path Path used to fetch the dataset.
    #
    # @option opts [Integer] :page Page number to start at.  Defaults to 1.
    #
    # @option opts [Integer] :results_per_page Number of results to include
    # per page.  Defaults to 50.
    #
    # @option opts [Boolean] :pretty Controlls pretty formating of the encoded
    # json.  Defaults to true.
    #
    # @option opts [Integer] :inline_relations_depth Depth to recursively
    # exapend relationships in addition to providing the URLs.
    #
    # @option opts [Integer] :max_inline Maximum number of objects to
    # expand inline in a relationship.
    #
    # @option opts [String] :order_by Column to order results by
    #
    # @option opts [String] :order The order to sort results in; either "asc"
    # (ascending) or "desc" (descending).  Defaults to "asc".
    def initialize(controller, ds, path, opts, request_params = {})
      page       = opts[:page] || 1
      page_size  = opts[:results_per_page] || 50
      criteria = order_by(opts, controller, ds)

      @paginated = ds.order_by(*criteria).extension(:pagination).paginate(page, page_size)
      @serialization = opts[:serialization] || ObjectSerialization

      @controller = controller
      @path = path
      @opts = opts
      @request_params = request_params
    end

    # Determines the column to order the paged dataset by.
    #
    # @returns [Symbol] The name of the column to order by.
    def order_by(opts, controller, ds)

      requested_order_by = opts[:order_by] ? opts[:order_by].to_sym : nil
      order_by = requested_order_by && ds.columns.include?(requested_order_by) ? requested_order_by : controller.default_order_by

      if opts[:order] && opts[:order] == 'desc'
        order_by = Sequel.desc(order_by)
      end

      order_by
    end

    # Pagination
    #
    # @return [String] Json encoding pagination of the dataset.
    def render_json

      parents, relations = resources

      res = {
        :total_results => @paginated.pagination_record_count,
        :total_pages   => @paginated.page_count,
        :prev_url      => prev_page_url,
        :next_url      => next_page_url,
        :resources     => parents,
      }

      if relations
        res[:relations] = relations
      end

      Yajl::Encoder.encode(res, :pretty => @opts[:pretty] == 1 ? true : ObjectSerialization.pretty_default)
    end

    private

    def resources

      parents = []
      relations = @opts[:orphan_relations] == 1 ? {} : nil

      @paginated.all.map do |m|
        hash = @serialization.to_hash(@controller, m, @opts, 0, [], relations)
        parents.push(hash)
      end

      return parents, relations
    end

    def prev_page_url
      @paginated.prev_page ? url(@paginated.prev_page) : nil
    end

    def next_page_url
      @paginated.next_page ? url(@paginated.next_page) : nil
    end

    def url(page)
      params = {
        'page' => page,
        'results-per-page' => @paginated.page_size
      }
      params['inline-relations-depth'] = @opts[:inline_relations_depth] if @opts[:inline_relations_depth]
      params['q'] = @opts[:q] if @opts[:q]
      @controller.preserve_query_parameters.each do |preseved_param|
        params[preseved_param] = @request_params[preseved_param] if @request_params[preseved_param]
      end

      params['orphan_relations'] = @opts[:orphan_relations] if @opts[:orphan_relations]
      params['order'] = @opts[:order] if @opts[:order]
      params['order-by'] = @opts[:order_by] if @opts[:order_by]
      params['pretty'] = @opts[:pretty] if @opts[:pretty]
      params['exclude-relations'] = @opts[:exclude_relations] if @opts[:exclude_relations]
      params['include-relations'] = @opts[:include_relations] if @opts[:include_relations]

      uri = Addressable::URI.parse(@path)
      uri.query_values = params
      uri.normalize.request_uri
    end
  end
end
