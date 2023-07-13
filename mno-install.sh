#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./sno-install.sh config.yaml
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

set -euoE pipefail
set -o nounset

usage(){
  echo "Usage : $0 config-file"
  echo "Example : $0 config-compact.yaml"
}

if [ $# -lt 1 ]
then
  usage
  exit
fi

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then 
  usage
  exit
fi

config_file=$1; shift
cluster_name=$(yq '.cluster.name' $config_file)
masters_bmc_address=($(yq '.hosts.masters[].bmc.address' $config_file))
masters_bmc_userpass=($(yq '.hosts.masters[].bmc.userpass' $config_file))
masters_bmc_uuid=($(yq '.hosts.masters[].bmc.node_uuid' $config_file))
iso=$(yq '.iso.address' $config_file)

for i in "${!masters_bmc_address[@]}"; do
  echo "$i -> ${masters_bmc_address[$i]} : ${masters_bmc_userpass[$i]} : ${masters_bmc_uuid[$i]} "
  node-boot.sh ${masters_bmc_address[$i]} ${masters_bmc_userpass[$i]} $iso ${masters_bmc_uuid[$i]}
done


if [ ! -z "$(yq '.hosts.workers' $config_file)" ]; then
  workers_bmc_address=($(yq '.hosts.workers[].bmc.address // ""' $config_file))
  workers_bmc_userpass=($(yq '.hosts.workers[].bmc.userpass' $config_file))
  workers_bmc_uuid=($(yq '.hosts.workers[].bmc.node_uuid' $config_file))

  for i in "${!workers_bmc_address[@]}"; do
    echo "$i -> ${workers_bmc_address[$i]} : ${workers_bmc_userpass[$i]}"
    node-boot.sh ${workers_bmc_address[$i]} ${workers_bmc_userpass[$i]} $iso ${workers_bmc_uuid[$i]}
  done
fi

rendezvousIP=$(yq '.hosts.masters[0].ip' $config_file)

assisted_rest=http://$rendezvousIP:8090/api/assisted-install/v2/clusters
if [ "ipv6" = "$(yq '.host.stack' $config_file)" ]; then
  assisted_rest=http://[$rendezvousIP]:8090/api/assisted-install/v2/clusters
fi

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $assisted_rest)" != "200" ]]; do
  echo -n "."
  sleep 2;
done

echo
echo "Installing in progress..."

curl --silent $assisted_rest |jq

while [[ "\"installing\"" != $(curl --silent $assisted_rest |jq '.[].status') ]]; do
  echo "-------------------------------"
  curl --silent $assisted_rest |jq
  sleep 5
done

echo
echo "-------------------------------"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $assisted_rest)" == "200" ]]; do
  total_percentage=$(curl --silent $assisted_rest |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    echo "Installation in progress: completed $total_percentage/100"
  fi
  sleep 15;
done

echo "-------------------------------"
echo "Node Rebooted..."
echo "Installation still in progress, oc command will be available soon, please check the installation progress with oc commands."
echo "Enjoy!"
