class NMesosK8s::K8sService
  include NMesosK8s::K8sObject

  def initialize(config, container_tag, environment, username = 'unknown', should_output = true, enable_temporary_service_mode)
    @config = config
    @container_tag = container_tag
    @environment = environment
    @username = username
    @should_output = should_output
    @enable_temporary_service_mode = enable_temporary_service_mode
  end

  def generate
    return {} unless service?
    return {} if @enable_temporary_service_mode

    $stderr.puts "Generating service...".blue if @should_output

    service = {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'name' => app_name,
        'labels' => {
          'ServiceName' => service_name,
          'Environment' => @environment,
          'DeployUser' => @username,
          'NmesosK8sVersion' => NMESOS_K8S_VERSION
        },
      },

      'spec' => {
        'selector' => {
          'ServiceName' => service_name,
          'Environment' => @environment
        },

        'ports' => get_service_ports,
        'type' => 'NodePort',
      }
    }

    # Insert namespace if it has been defined in nmesos @config
    namespace = get_namespace
    service['metadata']['namespace'] = namespace if namespace

    $stderr.puts "Generated Kubernetes Service for '#{service_name}' service".green if @should_output

    service
  end

  private
    def get_service_ports()
      @config
      .dig('container', 'labels')
      .select { |k, v| k =~ /ServicePort_/ }
      .each_with_index
      .map do |(k, v), i|
        {
          'name'     => "port-#{i}",
          'protocol' => 'TCP',
          'port' => v.to_i,
          'targetPort' => k.split(/_/).last.to_i,
          'nodePort' => 20000 + v.to_i
        }
      end
    end
end
