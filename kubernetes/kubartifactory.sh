#!/bin/bash
# By Lily Williamson
# Created 20240228
# Sorry.
#
# The intent of this project is to eventually intake a namespace, postgres config files, and jfrog/jfrog-platform config files
# and generate a full artifactory platform using the jfrog/jfrog-platform helm chart, zalando postgres operator, and nginx ingress controller.
# Don't trust this for another few months from the creation date at least, I'm still figuring things out.
# My hope is to make something that does as much of the heavy lifting as possible and just reduces everything to a sea of flags or input files.

usage() {
  echo "Usage: $0 --namespace <namespace> --postgres-config <path-to-postgres-yaml> --jfrog-values <path-to-jfrog-values-yaml> --artifactory-replicas <X> --xray-replicas <Y>"
  echo "  --namespace            The Kubernetes namespace to deploy resources into."
  echo "  --postgres-config      Path to the PostgreSQL configuration file."
  echo "  --jfrog-values         Path to the JFrog Platform Helm values file."
  echo "  --system-yaml          Path to a system.yaml override file."
  echo "  --binarystore-xml      Path to a binarystore.xml override file."
  echo "  --artifactory-replicas Number of Artifactory replicas to deploy."
  echo "  --xray-replicas        Number of Xray replicas to deploy."
  exit 1
}

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --namespace) namespace="$2"; shift ;;
    --postgres-config) postgres_config="$2"; shift ;;
    --jfrog-values) jfrog_values="$2"; shift ;;
    --artifactory-replicas) artifactory_replicas="$2"; shift ;;
    --xray-replicas) xray_replicas="$2"; shift ;;
    --system-yaml) system_yaml="$2"; shift ;;
    --binarystore-xml) binarystore_xml="$2"; shift ;;
    *) echo "Unknown parameter: $1"; usage ;;
  esac
  shift
done

if [ -z "$namespace" ] || [ -z "$postgres_config" ] || [ -z "$jfrog_values" ]; then
  echo "Error: Missing required arguments. Namespace, postgres config, and jfrog values are required."
  usage
fi

echo "Creating Kubernetes namespace: $namespace"
kubectl create namespace "$namespace"
echo "Deploying PostgreSQL using configuration: $postgres_config"
kubectl apply -f "$postgres_config" --namespace "$namespace"

# Modify JFrog Helm Values with Dynamic Replica Counts
if [ -z "$artifactory_replicas" ] || [ -z "$xray_replicas" ]; then
  echo "Trusting $jfrog_values settings for replica counts";
else
  echo "Setting Artifactory replicas to $artifactory_replicas and Xray replicas to $xray_replicas"
  sed -i "s/artifactory.replicaCount:.*/artifactory.replicaCount: $artifactory_replicas/" "$jfrog_values"
  sed -i "s/xray.replicaCount:.*/xray.replicaCount: $xray_replicas/" "$jfrog_values"
fi
if [ ! -z "$binarystore_xml" ]; then
  kubectl -n $namespace create secret generic custom-binarystore --from-file=$binarystore_xml
fi
# Deploy JFrog Platform
echo "Deploying JFrog Platform in namespace: $namespace"
helm install jfrog-platform jfrog/artifactory-jcr -f "$jfrog_values" --namespace "$namespace"

echo "Deployment in $namespace is complete!"
