#!/bin/bash

set -e

source util/func.sh
source util/text-formatting.sh
source default-variables.sh

clusterEssentialsFileName="tanzu-cluster-essentials-darwin-amd64-$clusterEssentialsVersion.tgz"

main() {
  printHelp
  acquireSetupParams


  while true; do
      read -rp "Please review your installation parameters. Continue? (y)Yes/(n)No: " yn
      case $yn in
          [Yy]* )
            checkPreconditions
            createCluster "$clusterName"
            deployClusterEssentials

            break;;
          [Nn]* ) break;;
          * ) printf -- "Please answer yes or no\n";;
      esac
  done
}

printHelp() {
  printf -- "This script will create a new minikube cluster and install TAP on it.\n\n"
  printf -- "Requirements:\n"
  printf -- "- Minikube >= 1.31.2\n"
  printf -- "- kubectl CLI >= 1.28.2\n"
  printf -- "- tanzu CLI >= 1.0.0\n"
  printf -- "- Harbor registry with a user having write privileges\n"
  printf -- "- Enough hardware resources for a VM having %s virtual CPUs, %s MB of memory and %s of disk space\n" "$cpus" "$memory" "$diskSize"
  printf -- "- Archive %s in the same folder containing this script (you can download it from https://network.tanzu.vmware.com/products/tanzu-cluster-essentials/#/releases/1321952)\n\n" "$clusterEssentialsFileName"
}

acquireSetupParams() {
  clusterName=$(readVariableWithDefault "Name of the new k8s cluster" "$clusterName")
  k8sVersion="v"$(readVariableWithDefault "Kubernetes version" "$k8sVersion")
  tapVersion=$(readVariableWithDefault "TAP version" "$tapVersion")
  read -rp "Tanzu Network username: " tanzuNetworkUsername
  read -rsp "Tanzu Network password: " tanzuNetworkPassword
  printf -- "\n"
}

checkPreconditions() {
  printf -- "Checking preconditions.."
  errors=0

  if [ "$(minikube profile list | grep -c "$clusterName ")" -gt 0 ]; then
    printf -- "\n- ${RED}There is already a cluster with name \"%s\". Please delete it first.${CLEAR}" "$clusterName"
    errors=$((errors + 1))
  fi

  if [ ! -f "$clusterEssentialsFileName" ]; then
    printf -- "\n- ${RED}File \"%s\" is missing. Please add it to the folder containing this script.${CLEAR}" "$clusterEssentialsFileName"
    errors=$((errors + 1))
  fi

  if [ $errors -eq 0 ]; then
    # shellcheck disable=SC2059
    printf -- "${GREEN}OK${CLEAR}\n\n"
  else
    printf -- "\n"
    exit 1
  fi
}

createCluster() {
  printf -- "Creating k8s cluster"
  minikube start --profile="$clusterName" --memory="$memory" --cpus="$cpus" --disk-size="$diskSize" --kubernetes-version="$k8sVersion" --container-runtime=containerd --driver=vmware
  minikube profile "$clusterName"
}

deployClusterEssentials() {
  local clusterEssentialsInstallFolder="$HOME/tanzu-cluster-essentials"
  if [ -d "$clusterEssentialsInstallFolder" ]; then
    rm -rf "$clusterEssentialsInstallFolder";
  fi

  mkdir "$clusterEssentialsInstallFolder"
  tar -xvf "$clusterEssentialsFileName" -C "$clusterEssentialsInstallFolder"

  export INSTALL_BUNDLE="registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:$clusterEssentialsInstallBundleSha"
  export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"
  export INSTALL_REGISTRY_USERNAME=$tanzuNetworkUsername
  export INSTALL_REGISTRY_PASSWORD=$tanzuNetworkPassword
  cd "$clusterEssentialsInstallFolder"
  ./install.sh --yes
}

main "$@"; exit