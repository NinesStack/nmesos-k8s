require 'uri'

class NMesosK8s::ValidationError < RuntimeError; end

class NMesosK8s::EnvValidator
  include NMesosK8s::K8sObject

  def initialize(config)
    @config = config
  end

  # We need to make sure all the keys we expect are there
  def validate
    # Prevent deploying with deploy_freeze
    if @config.dig('container', 'deploy_freeze') && !@config.dig('container', 'kubernetes_unfreeze')
      return ['container.deploy_freeze prevents deployment']
    end

    return validate_statefulset if statefulset?
    return validate_scheduled_job if cronjob?

    # If we don't know what it is, let's assume it a `service`
    return validate_service
  end

  private
    REQUIRED_FIELDS = [
        ['container', 'env_vars'],
        ['container', 'image'],
        ['container', 'labels', 'HealthCheck'],
        ['container', 'labels', 'ServiceName'],
        ['container', 'labels', 'Environment'],
        ['container', 'ports'],
        ['resources', 'cpus'],
        ['resources', 'instances'],
        ['resources', 'memoryMb'],
        ['singularity', 'deployInstanceCountPerStep'],
        ['singularity', 'deployStepWaitTimeMs']
      ]

    def validate_service
      # Required fields
      errors = REQUIRED_FIELDS.inject([]) do |memo, entry|
        value = @config.dig(*entry)
        memo << (entry.join('.') + ' is missing') if value.nil? || value.to_s.empty?
        memo
      end

      unless (health_check_error = validate_health_check).empty?
        errors << health_check_error
      end

      errors
    end

    def validate_statefulset
      # Required fields
      errors = REQUIRED_FIELDS.inject([]) do |memo, entry|
        value = @config.dig(*entry)
        memo << (entry.join('.') + ' is missing') if value.nil? || value.to_s.empty?
        memo
      end
    end

    # If this is a service it must have a health check defined. If it's defined,
    # it must be one of: HttpGet, AlwaysSuccessful
    def validate_health_check
      path = ['container', 'labels', 'HealthCheck']

      if health_check = (@config.dig(*path))
        unless ['HttpGet', 'AlwaysSuccessful'].include?(health_check)
          return path.join('.') + ' must be either HttpGet or AlwaysSuccessful for services'
        end

        path = ['container', 'labels', 'HealthCheckArgs']
        if health_check == 'HttpGet'
          unless @config.dig(*path)
            return path.join('.') + ' must be defined for HTTP health checks'
          end

          parsed = URI.parse(@config.dig(*path).gsub(/([{} ]+|tcp)/, ''))
          unless ['http', 'https'].include?(parsed.scheme) && parsed.host
            return path.join('.') + ' must be a valid Sidecar-style HTTP or HTTPS URL'
          end
        end
      end

      ""
    end

    def validate_scheduled_job
      # Required fields
      required = [
        ['singularity', 'schedule'],
        ['container', 'image'],
        ['container', 'labels', 'ServiceName'],
        ['container', 'labels', 'Environment'],
        ['resources', 'cpus'],
        ['resources', 'memoryMb'],
      ].inject([]) do |memo, entry|
        value = @config.dig(*entry)
        memo << entry if value.nil? || value.to_s.empty?
        memo
      end

      # Excluded fields
      excluded = [
        ['container', 'labels', 'HealthCheck'],
      ].inject([]) do |memo, entry|
        value = @config.dig(*entry)
        memo << entry unless value.nil? || value.to_s.empty?
        memo
      end

      required + excluded
    end
end
