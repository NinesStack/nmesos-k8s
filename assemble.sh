#!/bin/bash -e

cat << EOF > /tmp/header
#!/usr/bin/env ruby

module NMesosK8s; end

require 'bundler/inline'

gemfile do
`sed 's/^/  /' Gemfile`
end

EOF

# Set the version of nmesos-k8s in version
gsed -i "s/NMESOS_K8S_VERSION = \"\"/NMESOS_K8S_VERSION = \"$APP_VSN\"/" lib/version.rb

# Nedd to include k8s_object first, then the rest
cat lib/nmesos_k8s/k8s_object.rb > /tmp/combined
find lib/nmesos_k8s -name "*.rb" | grep -v "k8s_object" | xargs cat >> /tmp/combined

cat /tmp/header lib/consts.rb lib/version.rb /tmp/combined bin/convert.rb > $APP_NAME
chmod 755 $APP_NAME
