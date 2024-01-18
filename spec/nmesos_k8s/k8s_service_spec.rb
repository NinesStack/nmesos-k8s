require_relative '../spec_helper'

describe NMesosK8s::K8sService do

  let(:tag)  { 'abba1212' }
  let(:env)  { 'dev' }
  let(:user) { 'beowulf' }

  let(:service_config) {
    {
      'container' => {
        'labels' => {
          'ServiceName' => 'chopper',
          'Environment' => 'dev',
          'ServicePort_8088' => '10007',
          'ServicePort_8089' => '10008',
          'HealthCheck' => 'HttpGet',
          'HealthCheckArgs' => 'http://{{ host }}:{{ tcp 10007 }}/health-check'
        },
      },
      'singularity' => {
        'deployInstanceCountPerStep' => 1,
        'autoAdvanceDeploySteps' => true,
        'deployStepWaitTimeMs' => 1000,
        'healthcheckUri' => '/health-check'
      }
    }
  }

  it 'skips configs that are not a service' do
    cron_config = {
      'container' => {
        'labels' => {
          'ServiceName' => 'sms-campaigns',
          'SidecarDiscover' => 'false'
        }
      }
    }

    service = NMesosK8s::K8sService.new(cron_config, tag, env, user, false)

    expect(service.generate).to be_empty
  end

  it 'generates a correct service when it is supposed to' do
    service = NMesosK8s::K8sService.new(service_config, tag, env, user, false).generate

    expect(service).not_to be_empty

    expect(service.dig('metadata', 'labels', 'ServiceName')).to eq('chopper')
    expect(service.dig('metadata', 'labels', 'Environment')).to eq(env)
    expect(service.dig('metadata', 'labels', 'DeployUser')).to eq(user)

    expect(service.dig('spec', 'ports', 0, 'name')).to eq('port-0')
    expect(service.dig('spec', 'ports', 0, 'port')).to eq(10007)
    expect(service.dig('spec', 'ports', 0, 'targetPort')).to eq(8088)
    expect(service.dig('spec', 'ports', 0, 'nodePort')).to eq(30007)

    expect(service.dig('spec', 'ports', 1, 'name')).to eq('port-1')
    expect(service.dig('spec', 'ports', 1, 'port')).to eq(10008)
    expect(service.dig('spec', 'ports', 1, 'targetPort')).to eq(8089)
    expect(service.dig('spec', 'ports', 1, 'nodePort')).to eq(30008)

    expect(service.dig('spec', 'type')).to eq('NodePort')

    expect(service.dig('spec', 'selector', 'ServiceName')).to eq('chopper')
    expect(service.dig('spec', 'selector', 'Environment')).to eq(env)
  end

  it 'generates a correct service when the ServiceName and app name do not match' do
    mismatch_config = service_config.dup
    mismatch_config['container']['labels']['ServiceName'] = 'chopper_suffix'

    service = NMesosK8s::K8sService.new(mismatch_config, tag, env, user, false).generate

    expect(service).not_to be_empty

    expect(service.dig('metadata', 'labels', 'ServiceName')).to eq('chopper_suffix')
    expect(service.dig('metadata', 'labels', 'Environment')).to eq(env)
    expect(service.dig('metadata', 'labels', 'DeployUser')).to eq(user)

    expect(service.dig('spec', 'ports', 0, 'port')).to eq(10007)
    expect(service.dig('spec', 'ports', 0, 'targetPort')).to eq(8088)
    expect(service.dig('spec', 'ports', 0, 'nodePort')).to eq(30007)

    expect(service.dig('spec', 'ports', 1, 'port')).to eq(10008)
    expect(service.dig('spec', 'ports', 1, 'targetPort')).to eq(8089)
    expect(service.dig('spec', 'ports', 1, 'nodePort')).to eq(30008)

    expect(service.dig('spec', 'type')).to eq('NodePort')

    expect(service.dig('spec', 'selector', 'ServiceName')).to eq('chopper_suffix')
    expect(service.dig('spec', 'selector', 'Environment')).to eq(env)
  end

  describe 'when specifying a namespace' do
    let(:custom_ns) { 'custom_ns' }
    let(:namespace_config) { service_config.merge('k8s' => { 'namespace' => custom_ns }) }

    it 'adds the namespace to the service manifest' do
      service = NMesosK8s::K8sService.new(namespace_config, tag, env, user, false).generate
      expect(service).not_to be_empty
      expect(service.dig('metadata', 'namespace')).to eq(custom_ns)
    end
  end

  describe 'when enabling temporary service mode' do
    let(:enable_temporary_service_mode) { true }

    it 'removes the service entirely' do
      service = NMesosK8s::K8sService.new(service_config, tag, env, user, false, true).generate
      expect(service).to be_empty
    end
  end
end
