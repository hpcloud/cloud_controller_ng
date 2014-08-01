# Stackato Bug 104692:
# Apps where the host isn't a suffix of the URL cause
# the route.name to be lost during export. This puts it back.

module VCAP::CloudController
  class StackatoRepairRouteNames
    def self.fix_missing_routes
      bad_routes = Route.where(:host => "").select(:id, :domain_id).all
      return if bad_routes.size == 0
      fixed_domains = {} # ID => final_name
      bad_routes.each do |bad_route|
        route_id = bad_route[:id]
        route = Route[route_id]
        domain_id = bad_route[:domain_id]
        domain = Domain[domain_id]
        route_name, domain_name = domain.name.split('.', 2)
        if route_name.size > 0 && domain_name
          route.host = route_name
          route.save
          fixed_domains[domain_id] ||= [domain, domain_name]
        end
      end
      fixed_domains.each_value do | domain, domain_name |
        domain.name = domain_name
        domain.save
      end
    end

  end # class StackatoRepairRouteNames
end # VCAP::CloudController
