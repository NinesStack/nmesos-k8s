require 'uri'

class NMesosK8s::K8sDeployment
  include NMesosK8s::K8sObject

  def initialize(config, container_tag, environment, instance_replicas, command_override, enable_probes, username = 'unknown', should_output = true, enable_temporary_service_mode)
    @config = config
    @container_tag = container_tag
    @environment = environment
    @instance_replicas = instance_replicas
    @command_override = command_override
    @enable_probes = enable_probes
    @username = username
    @should_output = should_output
    @enable_temporary_service_mode = enable_temporary_service_mode
  end

  def generate
    return {} if cronjob?
    return {} if statefulset?

    $stderr.puts "Generating deployment...".blue if @should_output

    ports = (@config.dig('container', 'ports') || []).each_with_index.map do |port, i|
      { 'name' => "port-#{i}", 'containerPort' => port }
    end

    # Get only the vars for the container that are NOT from Vault.
    # The Vault vars will be sent to the init container.
    env = get_non_vault_vars(@config.dig('container', 'env_vars'))
    vault_env = get_vault_vars(@config.dig('container', 'env_vars'))
    main_app_container_name = "#{@config.dig('container', 'image')}:#{@container_tag}"
    deployer_notifier_env = get_matching_env(@config.dig('container', 'env_vars'), "APPSIGNAL_APP_NAME") # AYO-DO, find a different way to get APPSIGNAL_APP_NAME

    deployment = {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name,
        'labels' => {
          'ServiceName' => service_name,
          'Environment' => @environment,
          'release' => @container_tag,
          'DeployUser' => @username,
          'NmesosK8sVersion' => NMESOS_K8S_VERSION
        }
      },

      'spec' => {
        'replicas' => @instance_replicas.nil? ? @config.dig('resources', 'instances') : @instance_replicas,

        'strategy' => {
          'type' => 'RollingUpdate',
          'rollingUpdate' => {
            'maxSurge' => @config.dig('singularity', 'deployInstanceCountPerStep'),
            'maxUnavailable' => 0,
          }
        },
        'minReadySeconds' => (@config.dig('singularity', 'deployStepWaitTimeMs') * 0.005 / 1000).to_i,

        'selector' => {
          'matchLabels' => {
            'ServiceName' => service_name,
            'Environment' => @environment
          }
        },

        'template' => {
          'metadata' => {
            'labels' => {
              'ServiceName' => service_name,
              'Environment' => @environment,
              'app' => app_name,
              'release' => @container_tag,
              'DeployUser' => @username,
              'NmesosK8sVersion' => NMESOS_K8S_VERSION
            },
            'annotations' => {
              'community.com/TailLogs' => relay_syslog?.to_s
            }
          },

          'spec' => {
            'affinity' => {
              'podAntiAffinity' => {
                'preferredDuringSchedulingIgnoredDuringExecution' => [{
                  'weight' => 100,
                  'podAffinityTerm' => {
                    'labelSelector' => {
                      'matchExpressions' => [{
                        'key' => 'ServiceName',
                        'operator' => 'In',
                        'values' => [
                          service_name
                        ],
                      }],
                    },
                    'topologyKey' => 'kubernetes.io/hostname'
                  },
                }],
              },
            },
            'imagePullSecrets' => [{
              'name' => 'privaterepoauth'
            }],
            'initContainers' => [
            {
                'name' => 'deployer-notifier',
                'image' => DEPLOYER_NOTIFIER_CONTAINER,
                'env' => deployer_notifier_env + [
                    { 'name' => 'SERVICE_NAME', 'value' => service_name },
                    { 'name' => 'ENVIRONMENT', 'value' => @environment },
                    { 'name' => 'CONTAINER_IMAGE', 'value' => main_app_container_name },
                    { 'name' => 'RELEASE', 'value' => @container_tag },
                    { 'name' => 'DEPLOY_USER', 'value' => @username },
                ],
            },
            {
              'name' => 'vault-init',
              'image' => VAULT_INIT_CONTAINER,
              'volumeMounts' => [{
                'name' => 'vault-vars',
                'mountPath' => VAULT_VAR_PATH
              }],
              'env' => vault_env,
              'command' => [ '/vault-init' ],
            }],
            'containers' => [{
              'image' => main_app_container_name,
              'command' => @command_override.nil? ? [] : @command_override.split(" "),
              'name' => app_name,

              'resources' => {
                'requests' => {
                  'cpu' => cpu_request_for(@config.dig('resources', 'cpus')),
                  'memory' => "#{@config.dig('resources', 'memoryMb')}Mi"
                },
                'limits' => {
                  'memory' => "#{@config.dig('resources', 'memoryMb')}Mi",
                  'cpu' => cpu_limit_for(@config.dig('resources', 'cpus')),
                }
              },

              'ports' => ports,
              'env' => env,

              'volumeMounts' => [{
                'name' => 'vault-vars',
                'mountPath' => VAULT_VAR_PATH
              }]
            }] + logproxy_container,
            'volumes' => [
              'name' => 'vault-vars',
              'emptyDir' => {}
            ]
          }
        }
      }
    }

    # Insert health checks if they are not empty in nmesos @config
    startup_probe = get_startup_probe
    liveness_probe = get_liveness_probe
    readiness_probe = get_readiness_probe

    if !startup_probe.empty? && @enable_probes
      deployment['spec']['template']['spec']['containers'].first['startupProbe'] = startup_probe
    end

    if !liveness_probe.empty? && @enable_probes
      deployment['spec']['template']['spec']['containers'].first['livenessProbe'] = liveness_probe
    end

    if !readiness_probe.empty? && @enable_probes
      deployment['spec']['template']['spec']['containers'].first['readinessProbe'] = readiness_probe
    end

    # Insert namespace if it has been defined in nmesos @config
    namespace = get_namespace
    deployment['metadata']['namespace'] = namespace if namespace

    # Insert sidecar discovery disabled only if specified
    discovery_disabled = get_sidecar_discovery
    deployment['metadata']['labels']['SidecarDiscover'] = discovery_disabled if discovery_disabled.to_s == 'false' || discovery_disabled == false

    # Insert node_selector if it has been defined in nmesos @config or use default
    node_selector = get_node_selector
    deployment['spec']['template']['spec']['nodeSelector'] = {}
    deployment['spec']['template']['spec']['nodeSelector']['Role'] = node_selector

    # Insert service account if it has been defined in nmesos @config
    service_account = get_service_account
    deployment['spec']['template']['spec']['serviceAccountName'] = service_account if service_account

    # Insert SERVICE_NAME (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    deployment['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_NAME',
      'value' => service_name
    }

    # Insert SERVICE_VERSION (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    deployment['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_VERSION',
      'value' => @container_tag
    }

    # Insert ProxyMode label if it exists
    deployment['spec']['template']['metadata']['labels']['ProxyMode'] = get_proxy_mode

    # Insert temporary service timestamp label if enable_temporary_service_mode set
    deployment['metadata']['labels']['TemporaryDeployment'] = 'true' if @enable_temporary_service_mode

    $stderr.puts "Generated Kubernetes Deployment for '#{service_name}' service".green if @should_output
    $stderr.puts "Temporary service mode enabled, please make sure to delete '#{service_name}' service once you have finished".red if @enable_temporary_service_mode

    deployment
  end

  private
    def get_health_check_port
      # Find all the labels, make a map like 10010 => 4000
      labels = @config.dig('container', 'labels').keys.select { |k| k =~ /^ServicePort_/ }
      ports = Hash[labels.map { |k| [ @config.dig('container', 'labels', k), k.sub(/ServicePort_/, '') ] }]

      # Find the actual port used in the health check @config
      /\w*tcp (?<check_service_port>\d+)/ =~ @config.dig('container', 'labels', 'HealthCheckArgs')
      abort 'failed to find matching service port for health check'.red if check_service_port.nil?

      ports[check_service_port].to_i
    end
end
