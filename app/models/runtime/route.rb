require 'cloud_controller/dea/client'
require 'uri'

module VCAP::CloudController
  class Route < Sequel::Model
    ROUTE_REGEX = /\A#{URI.regexp}\Z/.freeze

    class InvalidDomainRelation < VCAP::Errors::InvalidRelation; end
    class InvalidAppRelation < VCAP::Errors::InvalidRelation; end
    class InvalidOrganizationRelation < VCAP::Errors::InvalidRelation; end

    many_to_one :domain
    many_to_one :space, after_set: :validate_changed_space

    many_to_many :app_models, join_table: :apps_v3_routes

    many_to_many :apps,
      before_add:   :validate_app,
      after_add:    :handle_add_app,
      after_remove: :handle_remove_app

    add_association_dependencies apps: :nullify

    export_attributes :host, :path, :domain_guid, :space_guid
    import_attributes :host, :path, :domain_guid, :space_guid, :app_guids

    def before_destroy
      super
      delete_oauth_client
    end

    def fqdn
      host.empty? ? domain.name : "#{host}.#{domain.name}"
    end

    def as_summary_json
      {
        guid:   guid,
        host:   host,
        domain: {
          guid: domain.guid,
          name: domain.name
        }
      }
    end

    alias_method :old_path, :path
    def path
      old_path.nil? ? '' : old_path
    end

    def organization
      space.organization if space
    end

    def validate
      validates_presence :domain
      validates_presence :space

      errors.add(:host, :presence) if host.nil?

      validates_format /^([\w\-]+|\*)$/, :host if host && !host.empty?

      if path.empty?
        validates_unique [:host, :domain_id]  do |ds|
          ds.where(path: '')
        end
      else
        validates_unique [:host, :domain_id, :path]
      end

      validate_path

      main_domain = Kato::Config.get("cluster", "endpoint").gsub(/^api\./, '')
      builtin_routes = ["www", "api", "login", "ports", "aok", "logs", "doppler"]
      configured_routes = Kato::Config.get("cloud_controller_ng", "app_uris/reserved_list")
      reserved_domains = (builtin_routes + configured_routes).map { |x| "#{x}.#{main_domain}" }
      reserved_domains.push(URI(Kato::Config.get("cloud_controller_ng", "uaa/url")).host)

      if domain
        if host
          reserved_domains.each do |rdomain|
            if rdomain == fqdn
              errors.add(:host, :reserved_host)
              break
            end
          end

          if fqdn == main_domain
            errors.add(:host, :reserved_host)
          end
        end

        unless domain.wildcard
          errors.add(:host, :host_not_empty) unless (host.nil? || host.empty?)
        end
        validate_domain
      end

      validate_total_routes
      errors.add(:host, :domain_conflict) if domains_match?
    end

    def validate_path
      return if path == ''

      if !ROUTE_REGEX.match("pathcheck://#{host}#{path}")
        errors.add(:path, :invalid_path)
      end

      if path == '/'
        errors.add(:path, :single_slash)
      end

      if path[0] != '/'
        errors.add(:path, :missing_beginning_slash)
      end

      if path =~ /\?/
        errors.add(:path, :path_contains_question)
      end
    end

    def domains_match?
      return false if domain.nil? || host.nil? || host.empty?
      !Domain.find(name: fqdn).nil?
    end

    def validate_app(app)
      return unless space && app && domain

      unless app.space == space
        raise InvalidAppRelation.new(app.guid)
      end

      unless domain.usable_by_organization?(space.organization)
        raise InvalidDomainRelation.new(domain.guid)
      end

      register_oauth_client if app.sso_enabled
    end

    def validate_changed_space(new_space)
      apps.each{ |app| validate_app(app) }
      raise InvalidOrganizationRelation if domain && !domain.usable_by_organization?(new_space.organization)
    end

    def self.user_visibility_filter(user)
      {
        space_id: Space.dataset.join_table(:inner, :spaces_developers, space_id: :id, user_id: user.id).select(:spaces__id).union(
            Space.dataset.join_table(:inner, :spaces_managers, space_id: :id, user_id: user.id).select(:spaces__id)
          ).union(
            Space.dataset.join_table(:inner, :spaces_auditors, space_id: :id, user_id: user.id).select(:spaces__id)
          ).union(
            Space.dataset.join_table(:inner, :organizations_managers, organization_id: :organization_id, user_id: user.id).select(:spaces__id)
          ).union(
            Space.dataset.join_table(:inner, :organizations_auditors, organization_id: :organization_id, user_id: user.id).select(:spaces__id)
          ).select(:id)
      }
    end

    def register_oauth_client
      return if !client_secret.blank?
      self.class.db.transaction do
        self.client_secret = SecureRandom.base64(48)
        self.save
        client_info = {
          client_id: client_id,
          scope: %W{scim.me},
          client_secret: client_secret,
          authorized_grant_types: %W{authorization_code},
          authorities: %W{uaa.none},
          redirect_uri: sso_redirect_uri
        }
        begin
          oauth_client = scim_api.add :client, client_info
          logger.debug "Response from client registration: #{oauth_client.inspect}"
        rescue Exception => e
          logger.debug e.inspect
          raise e
        end
      end
    end

    def delete_oauth_client
      return if client_secret.nil?
      self.class.db.transaction do
        self.client_secret = nil
        # Test spec/unit/controllers/runtime/organizations_controller_spec.rb
        # 'when PrivateDomain is shared' failed when we merged in v201.
        # The route is in a partial state right now -- and we don't care if
        # it's not valid because we're in the middle of deleting it.
        save(:raise_on_failure => false)
        begin
          scim_api.delete :client, client_id
        rescue Exception => e
          if e.kind_of? CF::UAA::NotFound
            # ok, client already gone
            return
          end
          logger.debug e.inspect
          raise e
        end
      end
    end

    def client_id
      [fqdn, guid].join('-')
    end

    def in_suspended_org?
      space.in_suspended_org?
    end

    private

    def app_requires_restart
      apps.each do |app|
        app.restart_required = true
      end
    end

    def logger
      @logger ||= Steno.logger("cc.models.route")
    end

    def around_destroy
      loaded_apps = apps
      super

      loaded_apps.each do |app|
        handle_remove_app(app)

        if app.dea_update_pending?
          Dea::Client.update_uris(app)
        end
      end
    end

    def handle_add_app(app)
      app.handle_add_route(self)
    end

    def handle_remove_app(app)
      app.handle_remove_route(self)
    end

    def validate_domain
      res = valid_domain
      errors.add(:domain, :invalid_relation) if !res
    end

    def valid_domain
      return false if domain.nil?

      domain_change = column_change(:domain_id)
      return false if !new? && domain_change && domain_change[0] != domain_change[1]

      if (domain.shared? && !host.present?) ||
          (space && !domain.usable_by_organization?(space.organization))
        return false
      end

      true
    end

    def validate_total_routes
      return unless new? && space

      space_routes_policy = MaxRoutesPolicy.new(space.space_quota_definition, SpaceRoutes.new(space))
      org_routes_policy   = MaxRoutesPolicy.new(space.organization.quota_definition, OrganizationRoutes.new(space.organization))

      if space.space_quota_definition && !space_routes_policy.allow_more_routes?(1)
        errors.add(:space, :total_routes_exceeded)
      end

      if !org_routes_policy.allow_more_routes?(1)
        errors.add(:organization, :total_routes_exceeded)
      end
    end

    def scim_api
      if @scim_api.nil?
        @scim_api = StackatoScimUtils.scim_api
      end
      return @scim_api
    end

    def sso_redirect_uri
      ['https:/', fqdn, 'sso-callback'].join('/')
    end


  end
end
