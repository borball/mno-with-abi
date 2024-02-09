#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./mno-install.sh config.yaml
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

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

config_file=$1; shift
total_master=$(yq '.hosts.masters|length' $config_file)
iso=$(yq '.iso.address' $config_file)

send_command_to_all_hosts(){
  command=$1
  bmc_noproxy=$(yq ".hosts.common.bmc.bypass_proxy" $config_file)

  for ((i=0; i<$total_master;i++)); do
    bmc_address=$(yq ".hosts.masters[$i].bmc.address" $config_file)
    bmc_userpass=$(yq ".hosts.masters[$i].bmc.password" $config_file)
    bmc_uuid=$(yq ".hosts.masters[$i].bmc.node_uuid" $config_file)
    echo "Master $i -> ${bmc_address} : ${bmc_userpass} : ${bmc_uuid} "
    if [[ "true" == "${bmc_noproxy}" ]]; then
      $basedir/node-boot.sh $command "NOPROXY/${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    else
      $basedir/node-boot.sh $command "${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    fi

  done

  if [ ! -z "$(yq '.hosts.workers' $config_file)" ]; then
    total_worker=$(yq '.hosts.workers|length' $config_file)
    for ((i=0; i<$total_worker;i++)); do
      bmc_address=$(yq ".hosts.workers[$i].bmc.address" $config_file)
      bmc_userpass=$(yq ".hosts.workers[$i].bmc.password" $config_file)
      bmc_uuid=$(yq ".hosts.workers[$i].bmc.node_uuid" $config_file)
      echo "Worker $i -> ${bmc_address} : ${bmc_userpass} : ${bmc_uuid} "
    if [[ "true" == "${bmc_noproxy}" ]]; then
      $basedir/node-boot.sh $command "NOPROXY/${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    else
      $basedir/node-boot.sh $command "${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    fi
    done
  fi

}

send_command_to_all_hosts install

ipv4_enabled=$(yq '.hosts.common.ipv4.enabled // "" ' $config_file)
if [ "true" = "$ipv4_enabled" ]; then
  rendezvousIP=$(yq '.hosts.masters[0].ipv4.ip' $config_file)
  assisted_rest=http://$rendezvousIP:8090/api/assisted-install/v2/clusters
else
  rendezvousIP=$(yq '.hosts.masters[0].ipv6.ip' $config_file)
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

sleep 30

send_command_to_all_hosts post_install

echo "Enjoy!"
