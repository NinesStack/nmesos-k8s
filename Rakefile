$: << File.expand_path('lib')

if ENV.keys.any? { |k| k =~ /JAVA_MAIN_CLASS/ }
  # We're running under JRuby
  require 'warbler'

  Warbler::Task.new('jar')

  require 'tasks/build'
end

begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.rspec_opts = %w[--color --format=documentation]
    t.pattern = "spec/**/*_spec.rb"
  end

  task :default => [:spec]
rescue LoadError
  # don't generate Rspec tasks if we don't have it installed
end
