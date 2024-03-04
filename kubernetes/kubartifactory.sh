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
  echo "  --ingress-namespace    Ingress namespace, defaults to ingress-ngnix."
  echo "  --ingress-ip           Ingress IP (if it fails to grab the right one)"
  echo "  --postgres-values      Path to the PostgreSQL configuration file."
  echo "  --jfrog-values         Path to the JFrog Platform Helm values file."
  echo "  --system-yaml          Path to a system.yaml override file."
  echo "  --binarystore-xml      Path to a binarystore.xml override file."
  echo "  --artifactory-replicas Number of Artifactory replicas to deploy."
  echo "  --xray-replicas        Number of Xray replicas to deploy."
  echo "  --disable-ssl          Skip SSL termination."
  echo "  --ssl-cert             Path to SSL .crt or .pem or what have you."
  echo "  --ssl-key              Path to SSL key."
  exit 1
}
# Parse Arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --namespace) namespace="$2"; shift ;;
    --ingress-namespace) opt_ingress_namespace="$2"; shift ;;
    --ingress-ip) opt_ingress_ip="$2"; shift ;;
    --postgres-values) postgres_values="$2"; shift ;;
    --jfrog-values) jfrog_values="$2"; shift ;;
    --artifactory-replicas) artifactory_replicas="$2"; shift ;;
    --xray-replicas) xray_replicas="$2"; shift ;;
    --system-yaml) system_yaml="$2"; shift ;;
    --binarystore-xml) binarystore_xml="$2"; shift ;;
    --disable-ssl) opt_disable_ssl=1; shift ;;
    --ssl-cert) ssl_cert="$2"; shift ;;
    --ssl-key) ssl_key="$2"; shift ;;
    *) echo "Unknown parameter: $1"; usage ;;
  esac
  shift
done
## Boring default variable section
script_dir=$(dirname "$0")
unset disable_ssl; disable_ssl=${opt_disable_ssl:-0}
unset ingress_namespace; ingress_namespace=${opt_ingress_namespace:-"ingress-nginx"}

## "Bail-out" section
if [ -z "$namespace" ] || [ -z "$postgres_values" ] || [ -z "$jfrog_values" ]; then
  echo "Error: Missing required arguments. Namespace, postgres config, and jfrog values are required."
  usage
fi

## Variable-determining section
# Get the ingress controller's external IP unless provided
unset ingress_ip; if [ -z "$opt_ingress_ip" ]; then 
  ingress_ip=`kubectl get svc -n $ingress_namespace ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
else
  ingress_ip=$opt_ingress_ip
fi



echo "Creating Kubernetes namespace: $namespace"
kubectl create namespace "$namespace"
if [ $disable_ssl -eq 0 ]; then
  echo "Saving SSL certs as ${namespace}-ssl in the namespace"
  kubectl create secret tls "${namespace}-ssl" --cert="$ssl_cert" --key="$ssl_key" --namespace "$namespace"
  
echo "Deploying PostgreSQL using configuration: $postgres_values"
kubectl apply -f "$postgres_values" --namespace "$namespace"

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
  helm upgrade --install artifactory --namespace artifactory jfrog/jfrog-platform -f "$script_dir/binarystore-values.yaml"
fi
if [ ! -z "$system_yaml" ]; then
  # Make sure this is in the values.yaml:
  #systemYamlOverride:
  #  existingSecret: system-yaml
  #  dataKey: "$system_yaml" # but fill this in for realsies
  kubectl create secret generic system-yaml --from-file "$system_yaml" --namespace "$namespace"
# Deploy JFrog Platform
echo "Deploying JFrog Platform in namespace: $namespace"
helm install jfrog-platform jfrog/jfrog-platform -f "$jfrog_values" --namespace "$namespace"

echo "Deployment in $namespace is complete!"
