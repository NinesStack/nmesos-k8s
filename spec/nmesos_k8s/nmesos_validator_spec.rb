require_relative '../spec_helper'
require 'rspec/collection_matchers'

describe NMesosK8s::Validator do
  context 'when only one env is set' do
    let(:config)    { { 'environments' => { 'dev' => { 'container' => { 'env_vars' => { 'SOMEKEY' => 'value' } } } } } }
    let(:validator) { NMesosK8s::Validator.new(config) }

    it 'it allows everything' do
      expect(validator.validate).to be_empty
    end
  end

  context 'when more than one env is set' do
    let(:config)         { { 'environments' => { 'dev' => dev_config, 'another' => another_config } } }
    let(:dev_config)     { { 'container' => { 'env_vars' => { 'SOMEKEY' => 'value' } } } }
    let(:another_config) { { 'container' => { 'env_vars' => { 'MISMATCH' => 'value' } } } }
    let(:validator)  { NMesosK8s::Validator.new(config) }

    it 'requires all the same env vars to be set' do
      result = validator.validate
      expect(result).to have_exactly(1).item
      expect(result.first).to match(/another missing \["SOMEKEY\"]/)
    end
  end
end
