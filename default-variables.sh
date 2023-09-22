# shellcheck disable=SC2034

memory=15000
cpus=10
diskSize="80g"

k8sVersion="1.27.4"
clusterName="tap"

tapVersion="1.6.3"
clusterEssentialsVersion="1.6.1"
# you can get this value from https://network.tanzu.vmware.com/products/tanzu-cluster-essentials#/releases/1358494/artifact_references
# (artifact reference "tanzu-cluster-essentials/cluster-essentials-bundle")
clusterEssentialsInstallBundleSha="2f538b69c866023b7d408cce6f0624c5662ee0703d8492e623b7fce10b6f840b"
