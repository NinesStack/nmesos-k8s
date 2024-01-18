module NMesosK8s::K8sObject
  def service_name
      @enable_temporary_service_mode ? "temporary_#{@config.dig('container', 'labels', 'ServiceName')}" : @config.dig('container', 'labels', 'ServiceName')
  end

  def app_name
    service_name.gsub('_', '-')
  end

  def service?
    !(@config.dig('container', 'labels') || {}).select { |k, v| k =~ /ServicePort_/ }.empty?
  end

  def cronjob?
    @config.dig('singularity', 'schedule')
  end

  def statefulset?
    @config.dig('k8s', 'workload_type') == 'statefulset'
  end

  def get_vault_vars(vars)
    vault_vars = (vars || [])
      .select { |var, val| val =~ %r{vault://} }
      .map { |var, val| { 'name' => var, 'value' => val } }
      .append( { 'name' => 'FILENAME', 'value' => '/vault/.init-env' } )

    vault_vars.append(nr_license_vars) if needs_logproxy?

    vault_vars
  end

  def get_non_vault_vars(vars)
    (vars || [])
      .select { |var, val| val !~ %r{vault://} }
      .map { |var, val| { 'name' => var, 'value' => val } }
  end

  def get_matching_env(vars, var_key)
    (vars || [])
      .select { |var, val| var == var_key}
      .map { |var, val| { 'name' => var, 'value' => val } }
  end

  # Should we relay syslog?
  def relay_syslog?
    relay_syslog = @config.dig('executor', 'env_vars', 'EXECUTOR_RELAY_SYSLOG') || 'false'
    startup_only = @config.dig('executor', 'env_vars', 'EXECUTOR_RELAY_SYSLOG_STARTUP_ONLY') || 'false'
    (relay_syslog == 'true') && (startup_only != 'true')
  end

  private
  def nr_license_vars
    { 'name' => 'NEW_RELIC_LICENSE_KEY', 'value' => 'vault://secret/infra/newrelic?key=license' }
  end

  def needs_logproxy?
    # If there are any APPSIGNAL configs, we assume this is an Elixir service
    # and therefore needs logproxy
    env_vars = @config.dig('container', 'env_vars')
    env_vars && env_vars.any? { |(k, v)| k =~ /APPSIGNAL/ }
  end

  # This config is added as an init container when logproxy is required by the service
  def logproxy_container
    unless needs_logproxy?
      return []
    end

    [
      {
        'name' => 'logproxy',
        'image' => LOGPROXY_CONTAINER,
        'volumeMounts' => [{ 'name' => 'vault-vars', 'mountPath' => '/vault'} ],
        'securityContext' => { 'capabilities' => { 'add' => ['NET_ADMIN'] } },
        'env' =>  [
          { 'name' => 'NEW_RELIC_ACCOUNT', 'value' => NEW_RELIC_ACCOUNT },
          { 'name' => 'LOGHOST', 'value' => LOGPROXY_LOG_HOST }
        ]
      }
    ]
  end

  def get_namespace
    @config.dig('k8s', 'namespace')
  end

  def get_service_account
    @config.dig('k8s', 'service_account_name')
  end

  def get_node_selector
    @config.dig('k8s', 'node_selector_name') || KUBERNETES_DEFAULT_NODE_GROUP
  end

  def get_sidecar_discovery
    # If enable_temporary_service_mode is enabled, set SidecarDiscover 'false', else dig for it in config 
    @enable_temporary_service_mode ? 'false' : @config.dig('container', 'labels', 'SidecarDiscover')
  end

  def get_proxy_mode
    @config.dig('container', 'labels', 'ProxyMode') || "http"
  end

  # Use the Sidecar deployment health check as the liveness check
  def get_liveness_probe
    if @config.dig('container', 'labels', 'HealthCheck') == 'HttpGet'
      # Example.com here is just used to get the original URL into a form
      # the will parse OK with `URI.parse`. Nothing more.
      uri = URI.parse(@config.dig('container', 'labels', 'HealthCheckArgs').sub(/{{.*}}/, 'example.com'))
      {
        'httpGet' => {
            'port' => get_health_check_port,
            'path' => uri.path
        },
        'periodSeconds' => 10
      }
    else
      # AlwaysSuccessful
      {}
    end
  end

  # Use the Singularity deployment health check as the readiness check
  def get_readiness_probe
    if @config.dig('container', 'labels', 'HealthCheck') == 'HttpGet'
      {
        'httpGet' => {
            'port' => get_health_check_port,
            'path' => @config['singularity']['healthcheckUri']
        },
        'periodSeconds' => 3
      }
    else
      {}
    end
  end

  # Use the Singularity deployment health check as the startup check
  def get_startup_probe
    if @config.dig('container', 'labels', 'HealthCheck') == 'HttpGet'
      {
        'httpGet' => {
            'port' => get_health_check_port,
            'path' => @config['singularity']['healthcheckUri']
        },
        'initialDelaySeconds' => 10,
        'failureThreshold' => 50,
        'periodSeconds' => 1
      }
    else
      {}
    end
  end

  def get_health_check_port
    # Find all the labels, make a map like 10010 => 4000
    labels = @config.dig('container', 'labels').keys.select { |k| k =~ /^ServicePort_/ }
    ports = Hash[labels.map { |k| [ @config.dig('container', 'labels', k), k.sub(/ServicePort_/, '') ] }]

    # Find the actual port used in the health check @config
    /\w*tcp (?<check_service_port>\d+)/ =~ @config.dig('container', 'labels', 'HealthCheckArgs')
    abort 'failed to find matching service port for health check'.red if check_service_port.nil?

    ports[check_service_port].to_i
  end

  def cpu_request_for(amount)
    "#{(amount.to_f * 1000).to_i}m"
  end

  def cpu_limit_for(amount)
    # Give 25% headroom over the top of the requested amount
    "#{(amount.to_f * 1000 * 1.25).to_i}m"
  end
end
