require "cloud_controller/dea/dea_client"
require 'uri'

module VCAP::CloudController
  class Route < Sequel::Model
    class InvalidDomainRelation < VCAP::Errors::InvalidRelation; end
    class InvalidAppRelation < VCAP::Errors::InvalidRelation; end

    many_to_one :domain
    many_to_one :space

    many_to_many :apps,
      before_add: :validate_app,
      after_add: :mark_app_routes_changed,
      after_remove: :mark_app_routes_changed

    add_association_dependencies apps: :nullify

    export_attributes :host, :domain_guid, :space_guid
    import_attributes :host, :domain_guid, :space_guid, :app_guids

    def before_destroy
      super
      delete_oauth_client
    end

    def fqdn
      host.empty? ? domain.name : "#{host}.#{domain.name}"
    end

    def as_summary_json
      {
        guid: guid,
        host: host,
        domain: {
          guid: domain.guid,
          name: domain.name
        }
      }
    end

    def organization
      space.organization if space
    end

    def validate
      validates_presence :domain
      validates_presence :space

      errors.add(:host, :presence) if host.nil?

      validates_format   /^([\w\-]+)$/, :host if (host && !host.empty?)
      validates_unique   [:host, :domain_id]

      main_domain = Kato::Config.get("cluster", "endpoint").gsub(/^api\./, '')
      builtin_routes = ["www", "api", "login", "ports", "aok", "logs"]
      configured_routes = Kato::Config.get("cloud_controller_ng", "app_uris/reserved_list")
      reserved_domains = (builtin_routes + configured_routes).map { |x| "#{x}.#{main_domain}" }
      reserved_domains.push(URI(Kato::Config.get("cloud_controller_ng", "uaa/url")).host)

      if domain
        reserved_domains.each do |rdomain|
          if rdomain == fqdn
            errors.add(:host, :reserved_host)
            break
          end
        end

        if fqdn == main_domain
          errors.add(:host, :reserved_host)
        end

        unless domain.wildcard
          errors.add(:host, :host_not_empty) unless (host.nil? || host.empty?)
        end

        if space && space.domains_dataset.filter(:id => domain.id).count < 1
          errors.add(:domain, :invalid_relation)
        end
      end

      validate_total_routes
    end

    def validate_app(app)
      return unless (space && app && domain)

      unless app.space == space
        raise InvalidAppRelation.new(app.guid)
      end

      unless domain.usable_by_organization?(space.organization)
        raise InvalidDomainRelation.new(domain.guid)
      end

      register_oauth_client if app.sso_enabled
    end

    def self.user_visibility_filter(user)
      orgs = Organization.filter(Sequel.or(
        managers: [user],
        auditors: [user],
      ))

      spaces = Space.filter(Sequel.or(
        developers: [user],
        auditors: [user],
        managers: [user],
        organization: orgs,
      ))

      {:space => spaces}
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
        save
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

    def logger
      @logger ||= Steno.logger("cc.models.route")
    end

    def around_destroy
      loaded_apps = apps
      super

      loaded_apps.each do |app|
        mark_app_routes_changed(app)
      end
    end

    def mark_app_routes_changed(app)
      app.routes_changed = true
      if app.dea_update_pending?
        VCAP::CloudController::DeaClient.update_uris(app)
      end
    end

    def validate_domain
      return unless domain

      if (domain.shared? && !host.present?) ||
            (space && !domain.usable_by_organization?(space.organization))
        errors.add(:domain, :invalid_relation)
      end
    end

    def validate_total_routes
      return unless new? && space

      unless MaxRoutesPolicy.new(space.organization).allow_more_routes?(1)
        errors.add(:organization, :total_routes_exceeded)
      end
    end

    def scim_api
      return @scim_api if @scim_api
      target = Kato::Config.get("cloud_controller_ng", 'uaa/url')
      secret = Kato::Config.get("cloud_controller_ng", 'aok/client_secret')
      token_issuer =
        CF::UAA::TokenIssuer.new(target, 'cloud_controller', secret)
      token = token_issuer.client_credentials_grant
      @scim_api = CF::UAA::Scim.new(target, token.auth_header)
      return @scim_api
    end

    def sso_redirect_uri
      ['https:/', fqdn, 'sso-callback'].join('/')
    end


  end
end
