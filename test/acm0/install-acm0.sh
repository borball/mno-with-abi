#!/bin/bash

cluster="acm0"
version=stable-4.18

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
root_path="$( cd "$(dirname "$0")/../.." >/dev/null 2>&1 ; pwd -P )"
iso="$root_path"/mno-iso.sh
mno_workspace="$root_path"/instances/$cluster
install="$root_path"/mno-install.sh
config="$basedir"/cluster-config.yaml
extra_manifests="$root_path"/extra-manifests

copy_extra_manifests(){
  cp -r "$basedir"/extra-manifests/day1/. $extra_manifests/day1/
}

install_ocp(){
  echo "Install OCP $cluster"
  rm -rf $mno_workspace
  $iso $config $version
  cp $mno_workspace/agent.x86_64.iso /var/www/html/iso/$cluster.iso
  cp $mno_workspace/auth/kubeconfig /etc/kubes/kubeconfig-$cluster.yaml
  $install
}

copy_extra_manifests
install_ocp