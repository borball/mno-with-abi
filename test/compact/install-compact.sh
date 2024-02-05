#!/bin/bash

cluster="compact"
version=4.12.45

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$0")/../.." >/dev/null 2>&1 ; pwd -P )"
iso="$root_path"/mno-iso.sh
mno_workspace="$root_path"/$cluster
install="$root_path"/mno-install.sh
config="$basedir"/cluster-config.yaml

install_ocp(){
  echo "Install OCP $cluster"
  rm -rf $mno_workspace
  $iso $config $version
  cp $mno_workspace/agent.x86_64.iso /var/www/html/iso/$cluster.iso
  cp $mno_workspace/auth/kubeconfig /root/workload-enablement/kubeconfigs/kubeconfig-$cluster.yaml
  $install $config
}

./create-kvms.sh

install_ocp