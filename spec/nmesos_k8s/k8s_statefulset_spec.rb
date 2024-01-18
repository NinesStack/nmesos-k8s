require_relative '../spec_helper'

describe NMesosK8s::K8sStatefulSet do

  let(:tag)      { 'abba1212' }
  let(:env)      { 'dev' }
  let(:user)     { 'beowulf' }
  let(:replicas) { 2 }

  let(:statefulset_config) {
    {
      'k8s' => {
        'workload_type' => 'statefulset',
      },
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
          'HealthCheckArgs' => 'http://{{ host }}:{{ tcp 10007 }}/health-check'
        },
        'env_vars' => {}
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

  it 'generates a correct statefulset when it is supposed to' do
    statefulset = NMesosK8s::K8sStatefulSet.new(statefulset_config, tag, env, replicas, user, false).generate

    expect(statefulset).not_to be_empty

    metadata = statefulset['metadata']
    expect(metadata).not_to be_nil
    expect(metadata).not_to be_empty

    expect(metadata['name']).to eq('chopper')

    expect(statefulset.dig('spec', 'replicas')).to eq(2)

    expect(statefulset.dig('spec', 'updateStrategy', 'type')).to eq('RollingUpdate')

    expect(statefulset.dig('spec', 'minReadySeconds')).to eq(0)

    expect(statefulset.dig('spec', 'selector', 'matchLabels')).to eq({'ServiceName'=>'chopper', 'Environment'=>env})
    expect(statefulset.dig('spec', 'template', 'metadata', 'labels')).to eq(
      {'DeployUser' => user, 'ServiceName'=>'chopper', 'Environment'=>env, 'app' => 'chopper', 'release' => tag, 'NmesosK8sVersion'=>NMESOS_K8S_VERSION}
    )

    expect(statefulset.dig('spec', 'template', 'metadata', 'annotations')).to eq({'community.com/TailLogs' => 'true'})

    spec_tmpl = statefulset.dig('spec', 'template', 'spec')
    expect(spec_tmpl).not_to be_nil
    expect(spec_tmpl).not_to be_empty
    expect(spec_tmpl['imagePullSecrets']).not_to be_empty
    expect(spec_tmpl['initContainers'].count).to eq(1)
    expect(spec_tmpl['initContainers'].count).to eq(1)
    expect(spec_tmpl.dig('initContainers', 0, 'volumeMounts').count).to eq(1)
    expect(spec_tmpl.dig('initContainers', 0, 'image')).to eq(VAULT_INIT_CONTAINER)
    expect(spec_tmpl.dig('containers').count).to eq(1)

    container = statefulset.dig('spec', 'template', 'spec', 'containers', 0)
    %w{ image name resources ports env volumeMounts }.each do |x|
      expect(container[x]).not_to be_empty
    end

    %w{ requests limits }.each do |x|
      expect(container.dig('resources', x, 'memory')).to eq("256Mi")
    end

    expect(container['ports'].count).to eq(1)
    expect(container['ports']).to eq([{'name'=>'port-0', 'containerPort'=>8088}])
    expect(container['env']).to eq([
      {'name' => 'KUBERNETES_STATEFULSET_HOSTNAME', 'valueFrom' => { 'fieldRef' => { 'fieldPath' => 'metadata.name'}}},
      {"name"=>"SERVICE_NAME", "value"=>"chopper"},
      {"name"=>"SERVICE_VERSION", "value"=>"abba1212"}
    ])
    expect(container['volumeMounts']).to eq([{'name'=>'vault-vars', 'mountPath'=>VAULT_VAR_PATH}])
  end

  it 'adds logproxy for Elixir containers' do
    statefulset_config = {
      'k8s' => {
        'workload_type' => 'statefulset',
      },
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

    statefulset = NMesosK8s::K8sStatefulSet.new(statefulset_config, tag, env, replicas, user, false).generate
    expect(statefulset).not_to be_empty

    containers = statefulset.dig('spec', 'template', 'spec', 'containers')
    expect(containers).not_to be_nil
    expect(containers.size).to eq(2)
    expect(containers[0]['name']).to eq('chopper')
    expect(containers[1]['name']).to eq('logproxy')
  end

  it 'adds the service name to affinity' do
    statefulset_config = {
      'k8s' => {
        'workload_type' => 'statefulset',
      },
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

    statefulset = NMesosK8s::K8sStatefulSet.new(statefulset_config, tag, env, replicas, user, false).generate
    expect(statefulset).not_to be_empty
    # Kubernetes configs are ridiculous! Look at this deep nesting.
    expect(statefulset.dig(
      'spec', 'template', 'spec', 'affinity', 'podAntiAffinity',
      'preferredDuringSchedulingIgnoredDuringExecution', 0, 'podAffinityTerm',
      'labelSelector', 'matchExpressions', 0, 'values', 0
    )).to eq('chopper')
  end

  describe 'when overriding replica count' do
    let(:new_replica_count) { 4 }

    it 'passes the override through to the config' do
      statefulset_config = {
        'k8s' => {
          'workload_type' => 'statefulset',
        },
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

      statefulset = NMesosK8s::K8sStatefulSet.new(statefulset_config, tag, env, new_replica_count, user, false).generate
      expect(statefulset).not_to be_empty
      # Kubernetes configs are ridiculous! Look at this deep nesting.
      expect(statefulset.dig('spec', 'replicas')).to eq(new_replica_count)
    end
  end

  describe 'when specifying a namespace or service account' do
    let(:custom_ns) { 'custom_ns' }
    let(:custom_sa) { 'custom_sa' }
    let(:namespace_config) { statefulset_config.merge(
      'k8s' => {
        'workload_type' => 'statefulset',
        'namespace' => custom_ns,
        'service_account_name' => custom_sa,
      })
    }

    it 'adds the namespace to the statefulset' do
      statefulset = NMesosK8s::K8sStatefulSet.new(namespace_config, tag, env, replicas, user, false).generate

      expect(statefulset).not_to be_empty
      expect(statefulset.dig('metadata', 'namespace')).to eq(custom_ns)
    end

    it'when specifying a service account' do
      statefulset = NMesosK8s::K8sStatefulSet.new(namespace_config, tag, env, replicas, user, false).generate

      expect(statefulset).not_to be_empty
      expect(statefulset.dig('spec', 'template', 'spec', 'serviceAccountName')).to eq(custom_sa)
    end
  end
end
