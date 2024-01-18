#!/bin/bash -e

# If we're running in CI, configure EKS credentials
if [ "$CONFIGURE_EKS_CREDENTIALS" ]; then
	echo "configuring aws eks credentials"
	aws eks update-kubeconfig --region us-west-2 --name dev --alias dev
	aws eks update-kubeconfig --region us-west-2 --name prod --alias prod
fi

exec ./nmesos-k8s "$@"
