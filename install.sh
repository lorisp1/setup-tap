#!/bin/bash

set -e

memory=15000
cpus=10
diskSize="80g"
k8sVersion="v1.27.4"

printf -- "This script will create a new minikube cluster and install TAP on it.\n"
printf -- "Requirements:\n"
printf -- "\t- Minikube >= 1.31.2\n"
printf -- "\t- kubectl CLI >= 1.28.2\n"
printf -- "\t- tanzu CLI >= 1.0.0\n"
printf -- "\t- Harbor registry with a user having write privileges\n"
printf -- "\t- Enough resources for a VM having %s virtual CPUs, %s MB of memory and %s of disk space\n" $cpus $memory $diskSize

while true; do
    read -rp "Continue? (y)Yes/(n)No: " yn
    case $yn in
        [Yy]* )
            printf -- "Enter the name of the new k8s cluster:\n"
            read -r clusterName
            printf -- "Creating k8s cluster"
            minikube start --profile="$clusterName" --memory=$memory --cpus=$cpus --disk-size=$diskSize --kubernetes-version=$k8sVersion --container-runtime=containerd --driver=vmware

            break;;
        [Nn]* ) break;;
        * ) printf -- "Please answer yes or no\n";;
    esac
done