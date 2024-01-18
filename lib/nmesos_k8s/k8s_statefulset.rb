require 'uri'

class NMesosK8s::K8sStatefulSet
  include NMesosK8s::K8sObject

  def initialize(config, container_tag, environment, instance_replicas, username = 'unknown', should_output = true)
    @config = config
    @container_tag = container_tag
    @environment = environment
    @instance_replicas = instance_replicas
    @username = username
    @should_output = should_output
  end

  def generate
    return {} unless statefulset?

    $stderr.puts "Generating statefulset...".blue if @should_output

    ports = (@config.dig('container', 'ports') || []).each_with_index.map do |port, i|
      { 'name' => "port-#{i}", 'containerPort' => port }
    end

    # Get only the vars for the container that are NOT from Vault.
    # The Vault vars will be sent to the init container.
    env = get_non_vault_vars(@config.dig('container', 'env_vars'))
    # Use the kubernetes downward api to define statefulset hostnames so we can get the ordinal value for
    # services that need to be aware of what instance of a service is running e.g. for kinesis and benthos apps
    # an example hostname would be my-pod-24tg24g-2424g-0
    env << { 'name' => 'KUBERNETES_STATEFULSET_HOSTNAME', 'valueFrom' => { 'fieldRef' => { 'fieldPath' => 'metadata.name' } } }

    vault_env = get_vault_vars(@config.dig('container', 'env_vars'))

    statefulset = {
      'apiVersion' => 'apps/v1',
      'kind' => 'StatefulSet',
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
        'serviceName' => service_name,
        'replicas' => @instance_replicas.nil? ? @config.dig('resources', 'instances') : @instance_replicas,

        'updateStrategy' => {
          'type' => 'RollingUpdate',
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
              'name' => 'vault-init',
              'image' => VAULT_INIT_CONTAINER,
              'volumeMounts' => [{
                'name' => 'vault-vars',
                'mountPath' => VAULT_VAR_PATH
              }],
              'env' => vault_env,
              'command' => [ '/vault-init' ],
            ],
            'containers' => [{
              'image' => "#{@config.dig('container', 'image')}:#{@container_tag}",
              'name' => app_name,

              'resources' => {
                'requests' => {
                  'cpu' => cpu_request_for(@config.dig('resources', 'cpus')),
                  'memory' => "#{@config.dig('resources', 'memoryMb')}Mi"
                },
                'limits' => {
                  'memory' => "#{@config.dig('resources', 'memoryMb')}Mi",
                  'cpu' => cpu_limit_for(@config.dig('resources', 'cpus'))
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
    liveness_probe = get_liveness_probe
    readiness_probe = get_readiness_probe

    unless liveness_probe.empty?
      statefulset['spec']['template']['spec']['containers'].first['livenessProbe'] = liveness_probe
    end

    unless readiness_probe.empty?
      statefulset['spec']['template']['spec']['containers'].first['readinessProbe'] = readiness_probe
    end

    # Insert namespace if it has been defined in nmesos @config
    namespace = get_namespace
    statefulset['metadata']['namespace'] = namespace if namespace

    # Insert node_selector if it has been defined in nmesos @config or use default
    node_selector = get_node_selector
    statefulset['spec']['template']['spec']['nodeSelector'] = {}
    statefulset['spec']['template']['spec']['nodeSelector']['Role'] = node_selector

    # Insert service account if it has been defined in nmesos @config
    service_account = get_service_account
    statefulset['spec']['template']['spec']['serviceAccountName'] = service_account if service_account

    # Insert SERVICE_NAME (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    statefulset['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_NAME',
      'value' => service_name
    }

    # Insert SERVICE_VERSION (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    statefulset['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_VERSION',
      'value' => @container_tag
    }

    $stderr.puts "Generated Kubernetes StatefulSet for '#{service_name}' service".green if @should_output

    statefulset
  end
end
