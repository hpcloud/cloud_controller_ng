class CollectdJSON
  def initialize(opts={})
    @rrddir = opts[:rrddir] || CollectdJSON.rrddir
#     @types  = opts[:types]  || CollectdJSON.types
  end

  # Entry point.
  def data(opts={})
    host             = opts[:host]
    plugin           = opts[:plugin]
    plugin_instances = opts[:plugin_instances][/\w.*/]
    instances        = plugin_instances.blank? ? '*' : '{' +
      plugin_instances.split('/').join(',') + '}'
    rrdglob          = "#{@rrddir}/#{host}/#{plugin}/#{instances}.rrd"

    start = case
    when opts[:start] && opts[:start].index('.')
      opts[:start].split('.').first
    when opts[:start]
      opts[:start]
    else
      (Time.now - 3600).to_i
    end

    finish = case
    when opts[:finish] && opts[:finish].index('.')
      opts[:finish].split('.').first
    when opts[:finish]
      opts[:finish]
    else
      Time.now.to_i
    end

    data = []

    Dir.glob(rrdglob).map do |rrdname|
      parts         = rrdname.gsub(/#{@rrddir}\//, '').split('/')
      host_name     = parts[0]
      plugin_name   = parts[1]
      instance_name = File.basename(parts[2], '.rrd')
      rrd = Errand.new(:filename => rrdname)

      data << {
        :plugin => plugin_name, :instance => instance_name,
        :host   => host_name,
        :start  => start,
        :finish => finish,
        :rrd    => rrd,
      }
    end

    encode(data)
  end
  
  private
  # Attempt to structure the JSON reasonably sanely, so the consumer (i.e. a
  # browser) doesn't have to do a lot of computationally expensive work.
  def encode(datas)
    structure = {}
    datas.each do |data|
      fetch = data[:rrd].fetch(
        :function => "AVERAGE",
        :start => data[:start],
        :finish => data[:finish]
      )
      rrd_data = fetch[:data]

      # A single rrd can have multiple data sets (multiple metrics within
      # the same file). Separate the metrics.
      rrd_data.each_pair do |source, metric|

        # Filter out NaNs and weirdly massive values so yajl doesn't choke
        metric.map! do |datapoint|
          case
          when datapoint && datapoint.nan?
            @tripped = true
            @last_valid
          when @tripped
            @last_valid
          else
            @last_valid = datapoint
          end
        end

        # Last value is always wack. Set to 0, so the timescale isn't off by 1.
        metric[-1] = 0.0
        host     = data[:host]
        plugin   = data[:plugin]
        instance = data[:instance]
        start    = data[:start].to_i
        finish   = data[:finish].to_i

        structure[host] ||= {}
        structure[host][plugin] ||= {}
        structure[host][plugin][instance] ||= {}
        structure[host][plugin][instance][source] ||= {}
        structure[host][plugin][instance][source][:start] ||= start
        structure[host][plugin][instance][source][:finish] ||= finish
        structure[host][plugin][instance][source][:data] ||= metric
      end
    end
    structure
  end
end
