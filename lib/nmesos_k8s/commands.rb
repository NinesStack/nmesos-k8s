module NMesosK8s::Commands
  def self.release(manifest, opts, generator)
    abort 'Cannot reach AWS. Is VPN up?'.red unless can_connect?

    if opts[:dry_run]
      # Using kubectl, let's apply the manifest we generated
      puts "Changes from '#{opts[:service_file]}' to '#{opts[:environment]}' would be\n".blue

      diff = NMesosK8s::KubectlWrapper.new(opts[:kubectl_path], opts[:environment], opts[:kubectl_log_level]).diff(manifest)
      if diff.empty?
        puts "NONE\n\nThis usually means that you are not logged into K8s.\n".blue
      else
        puts diff
      end

      $stderr.puts 'Done.'.green
      exit 0
    end

    # Using kubectl, let's apply the manifest we generated
    puts "Deploying '#{opts[:service_file]}' to '#{opts[:environment]}' with '#{opts[:kubectl_path]}'...\n".blue
    begin
      $stderr.puts NMesosK8s::KubectlWrapper.new(opts[:kubectl_path], opts[:environment], opts[:kubectl_log_level]).apply(manifest).yellow
    rescue NMesosK8s::KubectlError => e
      abort e.message.red
    end

    $stderr.puts 'Done.'.green

    # If we want to watch the deploy, then let's do that.
    if generator.service? && opts[:watch_pods]
      sleep(2)
      NMesosK8s::K8sKubectlPodWatcher.new.watch(opts[:kubectl_path], opts[:environment], generator.app_name)
    end
  end

  def self.delete(manifest, opts)
    abort 'Cannot reach AWS. Is VPN up?'.red unless can_connect?
    abort 'Refusing to delete in dry-run mode'.red if opts[:dry_run]

    # Using kubectl, let's delete the manifest we generated
    puts "Deleting '#{opts[:service_file]}' from '#{opts[:environment]}' with '#{opts[:kubectl_path]}'...\n".blue
    begin
      $stderr.puts NMesosK8s::KubectlWrapper.new(opts[:kubectl_path], opts[:environment], opts[:kubectl_log_level]).delete(manifest).yellow
    rescue NMesosK8s::KubectlError => e
      abort e.message.red
    end
    $stderr.puts 'Done.'.green
  end
end
