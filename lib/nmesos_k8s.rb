module NMesosK8s; end

require 'consts'
require 'version'

lib_path = File.join(File.dirname(__FILE__), 'nmesos_k8s')

require File.join(lib_path, 'k8s_object')

Dir[File.join(lib_path, '*')].each do |file|
  require File.realpath(file)
end
