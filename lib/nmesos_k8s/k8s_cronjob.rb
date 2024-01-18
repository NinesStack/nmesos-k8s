class NMesosK8s::K8sCronjob
  include NMesosK8s::K8sObject

  def initialize(config, container_tag, environment, username = 'unknown', should_output = true)
    @username = username
    @config = config
    @container_tag = container_tag
    @environment = environment
    @should_output = should_output
  end

  def generate
    return {} unless cronjob?

    $stderr.puts "Generating cron job...".blue if @should_output

    # Get only the vars for the container that are NOT from Vault.
    # The Vault vars will be sent to the init container.
    env = get_non_vault_vars(@config.dig('container', 'env_vars'))
    vault_env = get_vault_vars(@config.dig('container', 'env_vars'))

    cronjob = {
      'apiVersion' => 'batch/v1',
      'kind' => 'CronJob',
      'metadata' => {
        'name' => app_name,
        'labels' => {
          'ServiceName' => service_name,
          'Environment' => @environment,
          'release' => @container_tag,
          'DeployUser' => @username,
          'NmesosK8sVersion' => NMESOS_K8S_VERSION
        },
        'annotations' => {
          'community.com/TailLogs' => relay_syslog?.to_s
        }
      },

      'spec' => {
        'schedule' => @config.dig('singularity', 'schedule'),

        'jobTemplate' => {
          'spec' => {
            'ttlSecondsAfterFinished' => 100,
            'template' => {
              'spec' => {
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
                      'cpu' => cpu_limit_for(@config.dig('resources', 'cpus')),
                      'memory' => "#{@config.dig('resources', 'memoryMb')}Mi"
                    }
                  },
                  'volumeMounts' => [{
                    'name' => 'vault-vars',
                    'mountPath' => VAULT_VAR_PATH
                  }],
                  'env' => env,
                }] + logproxy_container,
                'volumes' => [
                  'name' => 'vault-vars',
                  'emptyDir' => {}
                ],
                'restartPolicy' => 'OnFailure',
              }
            }
          }
        }
      }
    }

    if command = @config.dig('container', 'command')
      cronjob['spec']['jobTemplate']['spec']['template']['spec']['containers'].first['command'] = command.split
    end

    # Insert namespace if it has been defined in nmesos @config
    namespace = get_namespace
    cronjob['metadata']['namespace'] = namespace if namespace

    # Insert sidecar discovery disabled only if specified
    discovery_disabled = get_sidecar_discovery
    cronjob['metadata']['labels']['SidecarDiscover'] = discovery_disabled if discovery_disabled.to_s == 'false' || discovery_disabled == false

    # Insert node_selector if it has been defined in nmesos @config or use default
    node_selector = get_node_selector
    cronjob['spec']['jobTemplate']['spec']['template']['spec']['nodeSelector'] = {}
    cronjob['spec']['jobTemplate']['spec']['template']['spec']['nodeSelector']['Role'] = node_selector

    # Insert service account if it has been defined in nmesos @config
    service_account = get_service_account
    cronjob['spec']['jobTemplate']['spec']['template']['spec']['serviceAccountName'] = service_account if service_account

    # Insert SERVICE_NAME (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    cronjob['spec']['jobTemplate']['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_NAME',
      'value' => service_name
    }

    # Insert SERVICE_VERSION (legacy from mesos, but used by some services) environment variable used by some Elixir based services
    cronjob['spec']['jobTemplate']['spec']['template']['spec']['containers'].first['env'] << {
      'name' => 'SERVICE_VERSION',
      'value' => @container_tag
    }

    $stderr.puts "Generated Kubernetes cronjob for '#{service_name}' service".green if @should_output

    cronjob
  end
end
