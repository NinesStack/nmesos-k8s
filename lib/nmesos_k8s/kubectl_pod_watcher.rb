require 'stringio'
require 'magritte'
require 'colorize'

class NMesosK8s::K8sKubectlPodWatcher
  def watch(kubectl_path, env, service_name)
    buffer = StringIO.new
    puts "\033[2J"

    1.upto(10) do
      puts "\033[H"
      buffer = describe_pods(service_name, kubectl_path, env, buffer)
      filter(buffer)

      break if buffer.string =~ /Started container/ && buffer.string !~ /Failed/

      buffer.truncate(0)
      sleep 3
    end
  rescue Interrupt
  end

  private def describe_pods(service_name, kubectl_path, env, buffer)
    Magritte::Pipe.from_input_string("")
      .out_to(buffer)
      .filtering_with("#{kubectl_path} --context #{env} describe pods #{service_name}")
    buffer
  rescue Errno::EPIPE
    raise NMesosK8s::KubectlError.new(buffer.string)
  end

  private def filter(buffer)
    capture = false

    buffer
      .string
      .split(/\n/)
      .select do |line|
        if line =~ /Events:/
          capture = true
        elsif line =~ /Name:/
          capture = false
        end

        capture
      end
      .each do |line|
        if line =~ /(Events|^  --)/
          puts line.blue
        elsif line =~ /Started/
          puts line.green
        elsif line =~ /Created/
          puts line.yellow
        elsif line =~ /(Error|Fail)/i
          puts line.red
        else
          puts "#{line}\n"
        end
      end
  end
end
