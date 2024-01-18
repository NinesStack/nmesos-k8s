require 'magritte'
require 'stringio'
require 'colorize'

class NMesosK8s::KubectlError < RuntimeError; end

class NMesosK8s::KubectlWrapper
  def initialize(path, env, kubectl_log_level)
    @path = path
    @env = env
    @kubectl_log_level = kubectl_log_level
  end

  def apply(yaml_str)
    output = StringIO.new
    error_exit = false
    begin
      Magritte::Pipe.from_input_string(yaml_str)
      .out_to(output)
      .filtering_with("#{kubectl} apply -f -")
    rescue Errno::EPIPE
      error_exit = true
    end

    raise NMesosK8s::KubectlError.new(output.string) if error_exit || output.string =~ /error:/

    output.string
  end

  def delete(yaml_str)
    output = StringIO.new
    error_exit = false
    begin
      Magritte::Pipe.from_input_string(yaml_str)
      .out_to(output)
      .filtering_with("#{kubectl} delete -f -")
    rescue Errno::EPIPE
      error_exit = true
    end

    raise NMesosK8s::KubectlError.new(output.string) if error_exit || output.string =~ /error:/

    output.string
  end

  def diff(yaml_str)
    output = StringIO.new
    begin
      Magritte::Pipe.from_input_string(yaml_str)
      .out_to(output)
      .filtering_with("#{kubectl} diff -f -")
    rescue Errno::EPIPE
      # diff always exits with exit code 1 if there is a difference. This is OK.
    end

    output.string.each_line.map do |line|
      if line =~ /^\+{3}/
        "\n-----------\n#{line}".colorize(:light_blue)
      elsif line =~ /^\+/
        line.colorize(color: :green)
      elsif line =~ /^-[^-]/
        line.colorize(:red)
      else
        # skip unchanged lines
      end
    end.join
  end

  private def kubectl
    "#{@path} --context #{@env} -v=#{@kubectl_log_level}"
  end
end
