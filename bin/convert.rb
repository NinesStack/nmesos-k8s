#!/usr/bin/env ruby

$: << File.expand_path('../lib', File.dirname(__FILE__))

require 'colorize'
require 'deep_merge'
require 'optimist'
require 'yaml'
require 'pathname'
require 'resolv'
require 'timeout'
require 'socket'
require 'mkmf'
require 'open-uri'

# Handle running both as a script, and from the assembled uni-script
if File.basename(Pathname.new($0).realpath) != 'nmesos-k8s'
  module NMesosK8s; end
  require 'nmesos_k8s'
end

# Check kubectl is installed
module MakeMakefile::Logging
  @logfile = File::NULL
  @quiet = true
end
kubectl_path = find_executable 'kubectl'

unless kubectl_path
  raise 'Could not find kubectl, please install it.'
end

SUB_COMMANDS = %w{ delete print release scale --version }
opts_parser = Optimist::Parser.new do
  version "#{NMESOS_K8S_VERSION}"
  banner "Deploy NMesos configs to Kubernetes\n\n  Sub-Commands: #{SUB_COMMANDS.join(', ')}\n".blue
  opt :environment,                   'The name of the environment to run in', :short => 'e', :default => 'dev'
  opt :service_file,                  'The YAML of the service to convert', :type => String, :required => true
  opt :tag,                           'The Docker tag to deploy', :type => String, :required => true
  opt :dry_run,                       'Should we just print the YAML?', :default => true
  opt :kubectl_path,                  'The path to the kubectl binary', :default => kubectl_path
  opt :kubectl_log_level,             'Override kubectl -v=log_verbosity_level', :default => "0"
  opt :watch_pods,                    'Watch the pods when deploying?', :default => true
  opt :instance_replicas,             'Override the instance replica count?', :type => Integer, :default => nil
  opt :command_override,              'Override the container command? (supports: deployment)', :type => String, :default => nil
  opt :enable_probes,                 'Enable startup, readiness and liveness probes (supports: deployment) - should ONLY be used for debugging, useful with --command-override', :default => true
  opt :enable_temporary_service_mode, 'Enable temporary service mode, prefixes service_name \'temporary_\', disables sidecar discovery, removes service and nodeports (to avoid conflicts with existing k8s service) and adds a temporary service label that is tracked', :default => false
end

cmd = ARGV.shift
opts = Optimist::with_standard_exception_handling(opts_parser) do
  raise Optimist::HelpNeeded if cmd == '--help'
  raise Optimist::VersionNeeded if cmd == '--version'
  abort "Invalid command: '#{cmd}'. Try one of: '#{SUB_COMMANDS.join("', ")}'".red unless SUB_COMMANDS.include?(cmd)
  raise Optimist::HelpNeeded if ARGV.empty? # show help screen

  opts_parser.parse(ARGV)
end

def check_version?
  begin
    # Open the URL and read its content
    release_version = URI.parse(VERSION_URL).read

    # Compare the content with the expected version
    if release_version.strip == NMESOS_K8S_VERSION.strip
      return true
    else
      abort "nmesos-k8s version #{NMESOS_K8S_VERSION} is out of date. Please upgrade to #{release_version}.".red
    end

  rescue OpenURI::HTTPError => e
    # Handle HTTP error (e.g., 404 Not Found)
    puts "HTTP Error while checking version: #{e.message}".red
    return true
  rescue StandardError => e
    # Handle other errors
    puts "Error while checking version: #{e.message}".red
    return true
  end
end

def load_config_file(filename)
  YAML.load_file(filename)
rescue Errno::ENOENT
  YAML.load_file(filename + '.yml')
end

def load_config(config, env)
  config['common'].deep_merge!(config['environments'][env])
end

def can_connect?
  begin
    Timeout::timeout(2) do
      begin
        addr = Resolv.getaddress 'vault.uw2.prod.sms.community'
        s = TCPSocket.new(addr, 8200)
        s.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        return false
      end
    end
  rescue Timeout::Error
  end

  return false
end

check_version?

$stderr.puts '-'.green*80
$stderr.puts ' nmesos -> Kubernetes conversion'.green
$stderr.puts '-'.green*80

$stderr.puts "Loading config '#{opts[:service_file]}' for #{opts[:environment]}".blue
full_config = load_config_file(opts[:service_file])
validator = NMesosK8s::Validator.new(full_config)
env_config = load_config(full_config, opts[:environment])

# Get the username of the person that is deploying
username = ENV.fetch('SUDO_USER', ENV.fetch('USER', 'unknown'))

# Dependencies we'll inject
env_validator = NMesosK8s::EnvValidator.new(env_config)
k8s_service = NMesosK8s::K8sService.new(env_config, opts[:tag], opts[:environment], username, opts[:enable_temporary_service_mode])
k8s_deployment = NMesosK8s::K8sDeployment.new(env_config, opts[:tag], opts[:environment], opts[:instance_replicas], opts[:command_override], opts[:enable_probes], username, opts[:enable_temporary_service_mode])
k8s_cronjob = NMesosK8s::K8sCronjob.new(env_config, opts[:tag], opts[:environment], username)
k8s_deployer = NMesosK8s::KubectlWrapper.new(kubectl_path.to_s, opts[:environment], opts[:kubectl_log_level])
k8s_statefulset = NMesosK8s::K8sStatefulSet.new(env_config, opts[:tag], opts[:environment], opts[:instance_replicas], username)

# Config generator
generator = NMesosK8s::ConfigGenerator.new(
  validator,
  env_validator,
  k8s_deployment,
  k8s_service,
  k8s_cronjob,
  k8s_statefulset
)

# Actually generate the manifest
manifest = begin
  generator.to_yaml
rescue NMesosK8s::ValidationError => e
  abort "Invalid YAML: #{e.message}".red
end

# Do the work we were asked to do with the manifest
case cmd
when 'delete'
  NMesosK8s::Commands.delete(manifest, opts)

when 'print'
  puts manifest

when 'release'
  NMesosK8s::Commands.release(manifest, opts, generator)

when 'scale'
  abort 'scale requires that --instance-replicas be set'.red if opts[:instance_replicas].nil?
  NMesosK8s::Commands.release(manifest, opts)

else
  puts "Unknown command: #{cmd}"
end
