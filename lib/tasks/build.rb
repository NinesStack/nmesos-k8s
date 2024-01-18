desc 'Build the executable JAR/script'
task :build => [:jar] do
  require 'fileutils'

  FileUtils.chdir(File.expand_path('../../..', __FILE__))

  # Concatenate the files together
  File.write(
    'nmesos-k8s',
    File.read('bin/stub.sh') + File.read('dist/nmesos-k8s.jar')
  )

  # Make it executable
  FileUtils.chmod(0755, 'nmesos-k8s')
end
