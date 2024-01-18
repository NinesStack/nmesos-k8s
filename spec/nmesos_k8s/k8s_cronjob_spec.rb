require_relative '../spec_helper'

describe NMesosK8s::K8sCronjob do

  let(:tag)          { 'abba1212' }
  let(:env)          { 'dev' }
  let(:user)         { 'beowulf' }
  let(:service_name) { 'doc_search_index_update' }
  let(:app_name)     { 'doc-search-index-update' }
  let(:schedule)     { '0 16 * * *' }

  let(:cronjob_config) {
    {
      'resources' => {
        'cpus' => 0.5,
        'memoryMb' => 256
      },
      'container' => {
        'labels' => {
          'ServiceName' => service_name,
        },
        'env_vars' => {
          'BEOWULF' => 'hrunting',
        }
      },
      'singularity' => {
        'schedule' => '0 16 * * *',
      },
      'executor' => {
        'env_vars' => {
          'EXECUTOR_RELAY_SYSLOG' => 'true'
        }
      }
    }
  }

  it 'generates a correct cronjob when it is supposed to' do
    cronjob = NMesosK8s::K8sCronjob.new(cronjob_config, tag, env, user, false).generate

    expect(cronjob).not_to be_empty
    expect(cronjob['kind']).to eq 'CronJob'

    metadata = cronjob['metadata']
    expect(metadata).not_to be_nil
    expect(metadata).not_to be_empty

    expect(metadata['name']).to eq(app_name)
    expect(metadata['labels']).to eq(
      {'DeployUser' => user, 'ServiceName'=>service_name, 'Environment'=>env, 'release' => tag, 'NmesosK8sVersion'=>NMESOS_K8S_VERSION}
    )

    expect(metadata.dig('labels', 'SidecarDiscover')).to be_nil

    expect(cronjob.dig('spec', 'schedule')).to eq schedule

    expect(cronjob.dig('spec', 'jobTemplate', 'spec', 'ttlSecondsAfterFinished')).to eq 100

    spec_tmpl = cronjob.dig('spec', 'jobTemplate', 'spec', 'template', 'spec')
    expect(spec_tmpl).not_to be_nil
    expect(spec_tmpl).not_to be_empty
    expect(spec_tmpl['imagePullSecrets']).not_to be_empty
    expect(spec_tmpl['initContainers'].count).to eq(1)
    expect(spec_tmpl['initContainers'].count).to eq(1)
    expect(spec_tmpl.dig('initContainers', 0, 'volumeMounts').count).to eq(1)
    expect(spec_tmpl.dig('initContainers', 0, 'image')).to eq(VAULT_INIT_CONTAINER)
    expect(spec_tmpl.dig('containers').count).to eq(1)

    container = spec_tmpl['containers'][0]
    %w{ image name resources env volumeMounts }.each do |x|
      expect(container).to have_key x
      expect(container[x]).not_to be_empty
    end

    %w{ requests limits }.each do |x|
      expect(container.dig('resources', x, 'memory')).to eq("256Mi")
    end

    expect(container['env']).to eq([
      {'name'=>'BEOWULF', 'value'=>'hrunting'},
      {"name"=>"SERVICE_NAME", "value"=>"doc_search_index_update"},
      {"name"=>"SERVICE_VERSION", "value"=>"abba1212"}
    ])
    expect(container['volumeMounts']).to eq([{'name'=>'vault-vars', 'mountPath'=>VAULT_VAR_PATH}])
  end

  it 'disables sidecar discovery' do
    cronjob_config = {
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
        'schedule' => '0 16 * * *'
      }
    }

    cronjob = NMesosK8s::K8sCronjob.new(cronjob_config, tag, env, user, false).generate
    expect(cronjob).not_to be_empty
    expect(cronjob.dig('metadata', 'labels', 'SidecarDiscover')).not_to be_nil
    expect(cronjob.dig('metadata', 'labels', 'SidecarDiscover')).to eq('false')
  end

  it 'adds logproxy for Elixir containers' do
    cronjob_config = {
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
        'healthcheckUri' => '/health-check',
        'schedule' => '0 16 * * *'
      }
    }

    cronjob = NMesosK8s::K8sCronjob.new(cronjob_config, tag, env, user, false).generate
    expect(cronjob).not_to be_empty

    containers = cronjob.dig('spec', 'jobTemplate', 'spec', 'template', 'spec', 'containers')

    expect(containers).not_to be_nil
    expect(containers.size).to eq(2)
    expect(containers[0]['name']).to eq('chopper')
    expect(containers[1]['name']).to eq('logproxy')
  end

  describe 'when specifying a namespace or service account' do
    let(:custom_ns) { 'custom_ns' }
    let(:custom_sa) { 'custom_sa' }
    let(:namespace_config) { cronjob_config.merge('k8s' => { 'namespace' => custom_ns }) }
    let(:sa_config) { cronjob_config.merge('k8s' => { 'service_account_name' => custom_sa }) }

    it 'adds the namespace to the cronjob' do
      cronjob = NMesosK8s::K8sCronjob.new(namespace_config, tag, env, user, false).generate

      expect(cronjob).not_to be_empty
      expect(cronjob.dig('metadata', 'namespace')).to eq(custom_ns)
    end

    it'when specifying a service account' do
      cronjob = NMesosK8s::K8sCronjob.new(sa_config, tag, env, user, false).generate

      expect(cronjob).not_to be_empty
      expect(cronjob.dig('spec', 'jobTemplate', 'spec', 'template', 'spec', 'serviceAccountName')).to eq(custom_sa)
    end
  end
end

