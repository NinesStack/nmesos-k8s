require_relative '../spec_helper'

describe NMesosK8s::K8sDeployment do

  let(:tag)      { 'abba1212' }
  let(:env)      { 'dev' }
  let(:user)     { 'beowulf' }
  let(:replicas) { 2 }
  let(:command)  { nil }
  let(:enable_probes) { false }

  let(:deployment_config) {
    {
      'resources' => {
        'instances' => 2,
        'cpus' => 1.5,
        'memoryMb' => 256
      },
      'container' => {
        'ports' => [8088],
        'labels' => {
          'ServiceName' => 'chopper',
          'Environment' => 'dev',
          'ServicePort_8088' => '10007',
          'HealthCheck' => 'HttpGet',
          'HealthCheckArgs' => 'http://{{ host }}:{{ tcp 10007 }}/health-check',
          'ProxyMode' => 'tcp'
        },
        'env_vars' => {
          'BEOWULF' => 'hrunting',
        },
        'image' => 'quay.io/shimmur/chopper'
      },
      'singularity' => {
        'deployInstanceCountPerStep' => 1,
        'autoAdvanceDeploySteps' => true,
        'deployStepWaitTimeMs' => 1000,
        'healthcheckUri' => '/health-check'
      },
      'executor' => {
        'env_vars' => {
          'EXECUTOR_RELAY_SYSLOG' => 'true'
        }
      }
    }
  }

  it 'generates a correct deployment when it is supposed to' do
    deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate

    expect(deployment).not_to be_empty

    metadata = deployment['metadata']
    expect(metadata).not_to be_nil
    expect(metadata).not_to be_empty

    expect(metadata['name']).to eq('chopper')

    expect(deployment.dig('spec', 'replicas')).to eq(2)

    expect(deployment.dig('spec', 'strategy', 'type')).to eq('RollingUpdate')
    expect(deployment.dig('spec', 'strategy', 'rollingUpdate', 'maxSurge')).to eq(1)
    expect(deployment.dig('spec', 'strategy', 'rollingUpdate', 'maxUnavailable')).to eq(0)

    expect(deployment.dig('spec', 'minReadySeconds')).to eq(0)

    expect(deployment.dig('spec', 'selector', 'matchLabels')).to eq({'ServiceName'=>'chopper', 'Environment'=>env})
    expect(deployment.dig('spec', 'template', 'metadata', 'labels')).to eq({
      'DeployUser' => user, 'ServiceName'=>'chopper',
      'Environment'=> env,
      'app' => 'chopper',
      'release' => tag,
      'NmesosK8sVersion' => NMESOS_K8S_VERSION,
      'ProxyMode' => 'tcp'
    })

    expect(deployment.dig('spec', 'template', 'metadata', 'labels', 'ProxyMode')).not_to be_nil

    expect(metadata.dig('labels', 'SidecarDiscover')).to be_nil
    expect(deployment.dig('spec', 'template', 'metadata', 'annotations')).to eq({'community.com/TailLogs' => 'true'})

    spec_tmpl = deployment.dig('spec', 'template', 'spec')
    expect(spec_tmpl).not_to be_nil
    expect(spec_tmpl).not_to be_empty
    expect(spec_tmpl['imagePullSecrets']).not_to be_empty
    expect(spec_tmpl['initContainers'].count).to eq(2)

    # it includes the deployer-notifier init container
    container = spec_tmpl.dig('initContainers', 0)
    expect(container.dig('image')).to eq(DEPLOYER_NOTIFIER_CONTAINER)
    expect(container.dig('name')).to eq('deployer-notifier')

    expect(container.dig('env')).to eq([
        { 'name' => 'SERVICE_NAME', 'value' => 'chopper' },
        { 'name' => 'ENVIRONMENT', 'value' => 'dev' },
        { 'name' => 'CONTAINER_IMAGE', 'value' => 'quay.io/shimmur/chopper:abba1212' },
        { 'name' => 'RELEASE', 'value' => tag },
        { 'name' => 'DEPLOY_USER', 'value' => user },
    ])

    # it includes the vault-init container
    expect(spec_tmpl.dig('initContainers', 1, 'volumeMounts').count).to eq(1)
    expect(spec_tmpl.dig('initContainers', 1, 'image')).to eq(VAULT_INIT_CONTAINER)
    expect(spec_tmpl.dig('containers').count).to eq(1)
    expect(spec_tmpl.dig('nodeSelector', 'Role')).to eq(KUBERNETES_DEFAULT_NODE_GROUP)

    expect(spec_tmpl.dig('containers', 0, 'command')).to be_empty

    container = deployment.dig('spec', 'template', 'spec', 'containers', 0)
    %w{ image name resources ports env volumeMounts }.each do |x|
      expect(container[x]).not_to be_empty
    end

    %w{ requests limits }.each do |x|
      expect(container.dig('resources', x, 'memory')).to eq("256Mi")
    end

    expect(container['ports'].count).to eq(1)
    expect(container['ports']).to eq([{'name'=>'port-0', 'containerPort'=>8088}])
    expect(container['env']).to eq([{'name'=>'BEOWULF', 'value'=>'hrunting'}, {"name"=>"SERVICE_NAME", "value"=>"chopper"}, {"name"=>"SERVICE_VERSION", "value"=>"abba1212"}])
    expect(container['volumeMounts']).to eq([{'name'=>'vault-vars', 'mountPath'=>VAULT_VAR_PATH}])
  end

  it 'adds logproxy for Elixir containers' do
    deployment_config = {
      'container' => {
        'labels' => {
          'ServiceName' => 'chopper',
          'Environment' => 'dev',
        },
        'env_vars' => {
          'APPSIGNAL_SOMETHING' => 'true'
        }
      },
      'singularity' => {
        'deployInstanceCountPerStep' => 1,
        'deployStepWaitTimeMs' => 1000,
        'healthcheckUri' => '/health-check'
      }
    }

    deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate
    expect(deployment).not_to be_empty

    containers = deployment.dig('spec', 'template', 'spec', 'containers')
    expect(containers).not_to be_nil
    expect(containers.size).to eq(2)
    expect(containers[0]['name']).to eq('chopper')
    expect(containers[1]['name']).to eq('logproxy')
    expect(deployment.dig('spec', 'template', 'metadata', 'labels', 'ProxyMode')).to eq('http')
  end

  it 'disables sidecar discovery' do
    deployment_config = {
      'container' => {
        'labels' => {
          'ServiceName' => 'chopper',
          'Environment' => 'dev',
          'SidecarDiscover' => 'false'
        },
        'env_vars' => {
          'APPSIGNAL_SOMETHING' => 'true'
        }
      },
      'singularity' => {
        'deployInstanceCountPerStep' => 1,
        'deployStepWaitTimeMs' => 1000,
        'healthcheckUri' => '/health-check',
      }
    }

    deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate
    expect(deployment).not_to be_empty
    expect(deployment.dig('metadata', 'labels', 'SidecarDiscover')).not_to be_nil
    expect(deployment.dig('metadata', 'labels', 'SidecarDiscover')).to eq('false')
  end

  it 'adds the service name to affinity' do
    deployment_config = {
      'container' => {
        'labels' => {
          'ServiceName' => 'chopper',
          'Environment' => 'dev',
        },
        'env_vars' => {}
      },
      'singularity' => {
        'deployInstanceCountPerStep' => 1,
        'deployStepWaitTimeMs' => 1000,
        'healthcheckUri' => '/health-check'
      }
    }

    deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate
    expect(deployment).not_to be_empty
    # Kubernetes configs are ridiculous! Look at this deep nesting.
    expect(deployment.dig(
      'spec', 'template', 'spec', 'affinity', 'podAntiAffinity',
      'preferredDuringSchedulingIgnoredDuringExecution', 0, 'podAffinityTerm',
      'labelSelector', 'matchExpressions', 0, 'values', 0
    )).to eq('chopper')
  end

  describe 'when overriding replica count' do
    let(:new_replica_count) { 4 }

    it 'passes the override through to the config' do
      deployment_config = {
        'container' => {
          'labels' => {
            'ServiceName' => 'chopper',
            'Environment' => 'dev',
          },
          'env_vars' => {}
        },
        'singularity' => {
          'deployInstanceCountPerStep' => 1,
          'deployStepWaitTimeMs' => 1000,
          'healthcheckUri' => '/health-check'
        }
      }

      deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, new_replica_count, command, enable_probes, user, false).generate
      expect(deployment).not_to be_empty
      # Kubernetes configs are ridiculous! Look at this deep nesting.
      expect(deployment.dig('spec', 'replicas')).to eq(new_replica_count)
    end
  end

  describe 'when specifying a namespace, service account or node selector' do
    let(:custom_ns) { 'custom_ns' }
    let(:custom_sa) { 'custom_sa' }
    let(:custom_node_selector) { 'custom_node_selector' }

    let(:namespace_config) { deployment_config.merge('k8s' => { 'namespace' => custom_ns }) }
    let(:sa_config) { deployment_config.merge('k8s' => { 'service_account_name' => custom_sa }) }
    let(:node_selector_config) { deployment_config.merge('k8s' => { 'node_selector_name' => custom_node_selector }) }

    it 'adds the namespace to the deployment' do
      deployment = NMesosK8s::K8sDeployment.new(namespace_config, tag, env, replicas, command, enable_probes, user, false).generate

      expect(deployment).not_to be_empty
      expect(deployment.dig('metadata', 'namespace')).to eq(custom_ns)
    end

    it 'add a service account' do
      deployment = NMesosK8s::K8sDeployment.new(sa_config, tag, env, replicas, command, enable_probes, user, false).generate

      expect(deployment).not_to be_empty
      expect(deployment.dig('spec', 'template', 'spec', 'serviceAccountName')).to eq(custom_sa)
    end

    it 'add a node selector' do
      deployment = NMesosK8s::K8sDeployment.new(node_selector_config, tag, env, replicas, command, enable_probes, user, false).generate

      expect(deployment).not_to be_empty
      expect(deployment.dig('spec', 'template', 'spec', 'nodeSelector', 'Role')).to eq(custom_node_selector)
    end
  end

  describe 'when specifiying a command' do
    let(:command) { '/bin/sleep 3000' }

    it 'adds a command override to the main container' do
      deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate

      expect(deployment).not_to be_empty
      expect(deployment.dig('spec', 'template', 'spec', 'containers', 0, 'command')).to eq(['/bin/sleep', '3000'])
    end
  end

  describe 'when disabling probes' do
    let(:enable_probes) { false }

    it 'removes startup, readiness and liveness probes' do
      deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false).generate

      expect(deployment).not_to be_empty
      expect(deployment.dig('spec', 'template', 'spec', 'containers', 0, 'startupProbe')).to be_nil
      expect(deployment.dig('spec', 'template', 'spec', 'containers', 0, 'readinessProbe')).to be_nil
      expect(deployment.dig('spec', 'template', 'spec', 'containers', 0, 'livenessProbe')).to be_nil
    end
  end

  describe 'when enabling temporary service mode' do
    let(:enable_temporary_service_mode) { true }

    it 'prefixes temporary_ to the service name' do
      deployment = NMesosK8s::K8sDeployment.new(deployment_config, tag, env, replicas, command, enable_probes, user, false, enable_temporary_service_mode).generate

      expect(deployment).not_to be_empty

      metadata = deployment['metadata']
      expect(metadata).not_to be_nil
      expect(metadata).not_to be_empty

      metadata = deployment['metadata']
      expect(metadata['name']).to eq('temporary-chopper')
      expect(metadata['labels']).to eq({
        'DeployUser' => user,
        'ServiceName'=>'temporary_chopper',
        'Environment'=> env,
        'release' => tag,
        'SidecarDiscover' => 'false',
        'TemporaryDeployment' => 'true',
        'NmesosK8sVersion' => NMESOS_K8S_VERSION,
      })
    end
  end
end
