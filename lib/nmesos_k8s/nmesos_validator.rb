class NMesosK8s::ValidationError < RuntimeError; end

class NMesosK8s::Validator
  include NMesosK8s::K8sObject

  def initialize(config)
    @config = config
  end

  def validate
    return ['no environments configured'] if environments.empty?

    env_diff
  end

  private
    def environments
      @config['environments'].keys
    end

    def vars_for_env(env)
      @config.dig('environments', env, 'container', 'env_vars') || {}
    end

  def env_diff
    environments.each_cons(2) do |env_a, env_b|
      a_vars = vars_for_env(env_a).keys
      b_vars = vars_for_env(env_b).keys

      a_only = a_vars - b_vars

      if a_only != []
        return ["Mismatch in env_vars #{env_a} vs #{env_b}: #{env_b} missing #{a_only}"]
      end

      b_only = b_vars - a_vars

      if b_only != []
        return ["Mismatch in env_vars #{env_b} vs #{env_a}: #{env_a} missing #{b_only}"]
      end
    end

    return []
  end
end
