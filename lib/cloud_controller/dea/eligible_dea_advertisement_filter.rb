class EligibleDeaAdvertisementFilter
  def initialize(dea_advertisements, app_id)
    @filtered_advertisements = dea_advertisements.dup
    @app_id = app_id
  end

  def only_with_disk(minimum_disk)
    @filtered_advertisements.select! { |ad| ad.has_sufficient_disk?(minimum_disk) }
    self
  end

  def only_from_zone(req_zone)
    req_zone = "default" unless (req_zone && (req_zone != ""))

    # if the ad.zones were manually configured, ignore the ad.zone
    ad_zone = ad.zone
    if(ad.zones != ["default"])
      ad_zone = nil
    end

    @filtered_advertisements.select! { |ad| (ad_zone == req_zone) || (ad.zones.include? req_zone) }
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

  def dc_with_fewest_instances_of_app
    dcs = {}
    @filtered_advertisements.each do |filtered_ad|
      dcs[filtered_ad.datacenter] ||= 0
      dcs[filtered_ad.datacenter] += filtered_ad.num_instances_of(@app_id)
    end
    minimum_instance_count = @filtered_advertisements.map { |ad| dcs[ad.datacenter] }.min
    @filtered_advertisements.select! { |ad| dcs[ad.datacenter] == minimum_instance_count }
    self
  end
end
