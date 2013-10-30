require 'errand'
require 'stackato/collectd_json'

module VCAP::CloudController
  class StackatoStatsController < RestController::Base

    def get_collectd
      if !params.has_key?('host') || !params.has_key?('plugin')
        raise Errors::StackatoRequiredParametersMissing.new('host, plugin')
      end

      collectd = CollectdJSON.new(:rrddir => '/var/lib/collectd/rrd')
      collectd_data = collectd.data(
          :host => params["host"],
          :plugin => params["plugin"],
          :plugin_instances => params["args"] || '',
          :start => params["start"],
          :finish => params["finish"]
      )

      Yajl::Encoder.encode({ :json => collectd_data })
    end

    get "/v2/stackato/stats/collectd", :get_collectd
  end
end