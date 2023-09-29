#!/bin/bash

set -e

source util/func.sh
source util/text-formatting.sh
source default-variables.sh

clusterEssentialsFileName="tanzu-cluster-essentials-darwin-amd64-$clusterEssentialsVersion.tgz"
tanzuImageRegistryHostname="registry.tanzu.vmware.com"
tapImageRepository="tanzu-application-platform"

main() {
  printHelp
  acquireSetupParams

  while true; do
      read -rp "Please review your installation parameters. Continue? (y)Yes/(n)No: " yn
      case $yn in
          [Yy]* )
            checkPreconditions
            createCluster
            deployClusterEssentials
            installTap
            createDeveloperNamespace
            printRecap
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
  printf -- "- An image registry with a user having write privileges\n"
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
  read -rp "Image registry hostname: " imageRegistryHostname
  read -rp "Image registry username: " imageRegistryUsername
  read -rsp "Image registry password: " imageRegistryPassword
   printf -- "\n"
  read -rsp "sudo password: " sudoPassword
  printf -- "\n\n"
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
  export INSTALL_BUNDLE="registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:$clusterEssentialsInstallBundleSha"
  export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"
  export INSTALL_REGISTRY_USERNAME=$tanzuNetworkUsername
  export INSTALL_REGISTRY_PASSWORD=$tanzuNetworkPassword

  local clusterEssentialsInstallFolder="$HOME/tanzu-cluster-essentials"
  if [ -d "$clusterEssentialsInstallFolder" ]; then
    rm -rf "$clusterEssentialsInstallFolder";
  fi

  mkdir "$clusterEssentialsInstallFolder"
  tar -xvf "$clusterEssentialsFileName" -C "$clusterEssentialsInstallFolder"
  pushd "$clusterEssentialsInstallFolder"
  ./install.sh --yes

  echo "$sudoPassword" | sudo -S cp "$clusterEssentialsInstallFolder"/kapp /usr/local/bin/kapp
  echo "$sudoPassword" | sudo -S cp "$clusterEssentialsInstallFolder"/imgpkg /usr/local/bin/imgpkg
  printf -- "\n"
  popd
}

installTap() {
  kubectl create ns tap-install

  tanzu secret registry add tap-registry \
    --username "$tanzuNetworkUsername" \
    --password "$tanzuNetworkPassword" \
    --server "$tanzuImageRegistryHostname" \
    --export-to-all-namespaces --yes --namespace tap-install

  tanzu secret registry add registry-credentials \
    --server   "$imageRegistryHostname" \
    --username "$imageRegistryUsername" \
    --password "$imageRegistryPassword" \
    --namespace tap-install \
    --export-to-all-namespaces \
    --yes

  tanzu package repository add tanzu-tap-repository \
    --url "$tanzuImageRegistryHostname/${tapImageRepository}/tap-packages:$tapVersion" \
    --namespace tap-install

  tanzu package repository get tanzu-tap-repository --namespace tap-install

  # workaround: we don't use --wait=true because a reconcile fail (e.g. for a timeout) would make the command fail, even
  # though reconcile would eventually succeed. Use an active poll instead, to be removed when 'package install' command is
  # resilient to temporary failures
  tanzu package install tap -p tap.tanzu.vmware.com -v "$tapVersion" --values-file tap-values.yaml -n tap-install --wait=false
  waitForReconcile
}

waitForReconcile() {
  local timeoutSeconds=10800 # 3 hours (downloading everything could take long)
  local elapsedSeconds=0
  local sleepInterval=5

  printf -- "Waiting for packages to reconcile (this can take long!). Timeout %s seconds\n" $timeoutSeconds
  until [ "$(kubectl -n tap-install get packageinstall tap -o jsonpath='{.status.conditions[*].type}')" = 'ReconcileSucceeded' ]
  do
    if [ $elapsedSeconds -lt $timeoutSeconds ]; then
      sleep $sleepInterval
      elapsedSeconds=$((elapsedSeconds + sleepInterval))
    else
      printf -- "Reconcile timeout expired. Exiting setup\n"
      exit 1
    fi
  done
}

createDeveloperNamespace() {
  kubectl create namespace dev
  kubectl label namespaces dev apps.tanzu.vmware.com/tap-ns=""
}

printRecap() {
  local tapGuiFqdn=$(kubectl get httpproxy -n tap-gui -o jsonpath='{.items[*].spec.virtualhost.fqdn}')
  local ingressPort=$(kubectl get svc envoy -n tanzu-system-ingress -o jsonpath='{.spec.ports[?(@.name == "https")].nodePort}')

  printf -- "\n\n"
  printf -- "====================================================\n"
  printf -- "Congratulations, TAP was successfully installed on cluster \"%s\"!\n" $clusterName
  printf -- "TAP Developer Portal can be reached at the following address (remember to configure your DNS accordingly): https://%s:%s\n" "$tapGuiFqdn" $ingressPort
}

main "$@"; exit