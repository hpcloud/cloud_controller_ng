class EligibleDeaAdvertisementFilter
  def initialize(dea_advertisements, app_id)
    @filtered_advertisements = dea_advertisements.dup
    @app_id = app_id

    @instance_counts_by_zones = Hash.new(0)
    dea_advertisements.each { |ad| @instance_counts_by_zones[ad.zone] += ad.num_instances_of(@app_id) }
  end

  def only_with_disk(minimum_disk)
    @filtered_advertisements.select! { |ad| ad.has_sufficient_disk?(minimum_disk) }
    self
  end

  def only_from_zone(req_zone)
    req_zone = "default" unless (req_zone && (req_zone != ""))
    @filtered_advertisements.select! { |ad| ad.accepts_zone?(req_zone) }
    self
  end

  def only_meets_needs(mem, stack)
    @filtered_advertisements.select! { |ad| ad.meets_needs?(mem, stack) }
    self
  end

  def only_fewest_instances_of_app
    fewest_instances_of_app = @filtered_advertisements.map { |ad| ad.num_instances_of(@app_id) }.min
    @filtered_advertisements.select! { |ad| ad.num_instances_of(@app_id) == fewest_instances_of_app }
    self
  end

  def upper_half_by_memory
    unless @filtered_advertisements.empty?
      @filtered_advertisements.sort_by! { |ad| ad.available_memory }
      min_eligible_memory = @filtered_advertisements[@filtered_advertisements.size/2].available_memory
      @filtered_advertisements.select! { |ad| ad.available_memory >= min_eligible_memory }
    end

    self
  end

  def sample
    @filtered_advertisements.sample
  end

  def az_with_fewest_instances_of_app
    azs = {}
    @filtered_advertisements.each do |filtered_ad|
      azs[filtered_ad.availability_zone] ||= 0
      azs[filtered_ad.availability_zone] += filtered_ad.num_instances_of(@app_id)
    end
    minimum_instance_count = @filtered_advertisements.map { |ad| azs[ad.availability_zone] }.min
    @filtered_advertisements.select! { |ad| azs[ad.availability_zone] == minimum_instance_count }
    self
  end
end
