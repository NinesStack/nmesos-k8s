require_relative '../spec_helper'
require 'yaml'

describe NMesosK8s::ConfigGenerator do
  let(:validator)     { double('validator') }
  let(:env_validator) { double('env_validator') }
  let(:deployment)    { double('deployment') }
  let(:service)       { double('service') }
  let(:cronjob)       { double('cronjob') }
  let(:statefulset)   { double('statefulset') }

  let(:generator)     { NMesosK8s::ConfigGenerator.new(validator, env_validator, deployment, service, cronjob, statefulset) }

  it 'calls all the generators' do
    expect(validator).to receive(:validate).and_return([])
    expect(env_validator).to receive(:validate).and_return([])
    expect(deployment).to receive(:generate).and_return('')
    expect(service).to receive(:generate).and_return('')
    expect(cronjob).to receive(:generate).and_return('')
    expect(statefulset).to receive(:generate).and_return('')

    generator.to_yaml
  end

  it 'raises an error when validation fails' do
    expect(validator).to receive(:validate).and_return(['intentional test error'])
    expect(env_validator).to receive(:validate).and_return([])
    expect { generator.to_yaml }.to raise_error(NMesosK8s::ValidationError)
  end

  it 'raises an error when env validation fails' do
    expect(validator).to receive(:validate).and_return([])
    expect(env_validator).to receive(:validate).and_return(['intentional test error'])
    expect { generator.to_yaml }.to raise_error(NMesosK8s::ValidationError)
  end

  it 'generates YAML when something is returned for each generator' do
    expect(validator).to receive(:validate).and_return([])
    expect(env_validator).to receive(:validate).and_return([])
    expect(deployment).to receive(:generate).and_return({'key' => 'value'})
    expect(service).to receive(:generate).and_return({'key' => 'value'})
    expect(cronjob).to receive(:generate).and_return({'key' => 'value'})
    expect(statefulset).to receive(:generate).and_return({'key' => 'value'})

    expect(generator.to_yaml).to eq(
      "---\nkey: value\n\n---\nkey: value\n\n---\nkey: value\n\n---\nkey: value\n"
    )
  end
end
