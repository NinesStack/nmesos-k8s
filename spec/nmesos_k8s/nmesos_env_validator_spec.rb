require_relative '../spec_helper'

describe NMesosK8s::EnvValidator do
  it 'prevents deployment when deploy_freeze is set' do
    empty_service_validator = NMesosK8s::EnvValidator.new(
      {'container' => {'deploy_freeze' => true}}
    )
    errors = empty_service_validator.validate

    expect(errors.size).to eq(1)
    expect(errors.first).to match(/deploy_freeze/)
  end

  it 'even when deploy_freeze is set, we can override with kubernetes_unfreeze' do
    empty_service_validator = NMesosK8s::EnvValidator.new(
      {'container' => { 'deploy_freeze' => true, 'kubernetes_unfreeze' => true } }
    )
    errors = empty_service_validator.validate.select { |x| x =~ /deploy_freeze/ }
    expect(errors).to eq []
  end

  context 'for Services' do
    it 'makes sure we have all the required fields' do
      definition = {
        'container' => { 'labels' => {'ServicePort_8800' => '4000' }}
      }
      empty_service_validator = NMesosK8s::EnvValidator.new(definition)
      errors = empty_service_validator.validate

      expect(errors.size).to eq(11)
    end

    context 'when evaluating health checks' do
      it 'validates checks are a valid type' do
        service_validator = NMesosK8s::EnvValidator.new(
          {'container' => {'labels' => { 'HealthCheck' => 'bad thing', 'ServicePort_8800' => '4000' }}}
        )
        errors = service_validator.validate

        health_check_errors = errors.select { |e| e =~ /HealthCheck must be either/ }
        expect(health_check_errors.size).to eq(1)
      end

      it 'validates that HttpGet checks have useable arguments' do
        service_validator = NMesosK8s::EnvValidator.new({
          'container' =>
            {'labels' => {
              'HealthCheck' => 'HttpGet',
              'HealthCheckArgs' => 'http://{{ host }}:{{ tcp 10007 }}/health-check',
              'ServicePort_8800' => '4000'
            }
          }
        })
        errors = service_validator.validate

        health_check_errors = errors.select { |e| e =~ /HealthCheck/ }
        expect(health_check_errors).to be_empty
      end

      it 'returns errors when HttpGet has missing arguments' do
        service_validator = NMesosK8s::EnvValidator.new({
          'container' =>
            {'labels' => {
              'HealthCheck' => 'HttpGet',
              'ServicePort_8800' => '4000'
            }
          }
        })
        errors = service_validator.validate

        health_check_errors = errors.select { |e| e =~ /HealthCheckArgs must be defined/ }
        expect(health_check_errors).not_to be_empty
      end

      it 'returns errors when HttpGet has invalid arguments' do
        service_validator = NMesosK8s::EnvValidator.new({
          'container' =>
            {'labels' => {
              'HealthCheck' => 'HttpGet',
              'HealthCheckArgs' => 'yo yo yo this is invalid',
              'ServicePort_8800' => '4000'
            }
          }
        })
        errors = service_validator.validate

        health_check_errors = errors.select { |e| e =~ /HealthCheck/ }
        expect(health_check_errors.size).to eq(1)
        expect(health_check_errors.first).to match(
          /HealthCheckArgs must be a valid Sidecar-style/
        )
      end
    end
  end

  context 'for Scheduled Jobs' do
    it 'makes sure we have all the required fields' do
      # Make sure this shows up as a scheduled job
      empty_job_validator = NMesosK8s::EnvValidator.new(
        {'singularity' => {'schedule' => 'anything'}}
      )
      errors = empty_job_validator.validate

      expect(errors.size).to eq(5)
    end

    it 'does not have a health check' do
      # Make sure this shows up as a scheduled job
      job_validator = NMesosK8s::EnvValidator.new({
        'singularity' => {
          'schedule' => 'anything',
        },
        'container' => {
          'labels' => {
            'HealthCheck' => 'HttpGet',
            'ServiceName' => 'test-service',
            'Environment' => 'dev'
          },
          'image' => 'test:123',
        },
        'resources' => {
          'cpus' => 0.1,
          'memoryMb' => 3
        }
      })
      errors = job_validator.validate

      expect(errors).to eq([['container', 'labels', 'HealthCheck']])
    end
  end
end
