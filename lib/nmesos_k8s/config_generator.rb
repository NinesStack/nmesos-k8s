class NMesosK8s::ConfigGenerator
  def initialize(validator, env_validator, deployment, service, cronjob, statefulset)
    @validator = validator
    @env_validator = env_validator
    @deployment = deployment
    @service = service
    @cronjob = cronjob
    @statefulset = statefulset
  end

  def to_yaml
    validate

    [@service.generate, @deployment.generate, @cronjob.generate, @statefulset.generate]
    .reject { |x| x.empty? }
    .map { |x| x.to_yaml }
    .join("\n")
  end

  def service_name
    @deployment.service_name || @cronjob.service_name || @statefulset.service_name
  end

  def app_name
    @deployment.app_name || @cronjob.app_name || @statefulset.app_name
  end

  def service?
    @service.service?
  end

  private
    def validate
      unless (errors = [@validator.validate, @env_validator.validate].flatten).empty?
        raise NMesosK8s::ValidationError.new(errors.join("\n" + ' '*16))
      end
    end
end
