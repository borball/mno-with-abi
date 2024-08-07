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

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$basedir/instances/$cluster_name
export KUBECONFIG=$cluster_workspace/auth/kubeconfig

send_command_to_all_hosts(){
  command=$1
  bmc_noproxy=$(yq ".hosts.common.bmc.bypass_proxy" $config_file)

  for ((i=0; i<$total_master;i++)); do
    bmc_address=$(yq ".hosts.masters[$i].bmc.address" $config_file)
    bmc_userpass=$(yq ".hosts.masters[$i].bmc.password" $config_file)
    bmc_uuid=$(yq -r ".hosts.masters[$i].bmc.node_uuid" $config_file)
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
      bmc_uuid=$(yq -r ".hosts.workers[$i].bmc.node_uuid" $config_file)
      echo "Worker $i -> ${bmc_address} : ${bmc_userpass} : ${bmc_uuid} "
    if [[ "true" == "${bmc_noproxy}" ]]; then
      $basedir/node-boot.sh $command "NOPROXY/${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    else
      $basedir/node-boot.sh $command "${bmc_address}" ${bmc_userpass} ${iso} ${bmc_uuid}
    fi
    done
  fi

}

SECONDS=0
send_command_to_all_hosts install

ipv4_enabled=$(yq '.hosts.common.ipv4.enabled // "" ' $config_file)
if [ "true" = "$ipv4_enabled" ]; then
  rendezvousIP=$(yq '.hosts.masters[0].ipv4.ip' $config_file)
  assisted_rest=http://$rendezvousIP:8090/api/assisted-install/v2/clusters
else
  rendezvousIP=$(yq '.hosts.masters[0].ipv6.ip' $config_file)
  assisted_rest=http://[$rendezvousIP]:8090/api/assisted-install/v2/clusters
fi

REMOTE_CURL="curl -s"
if [[ "true"=="${bmc_noproxy}" ]]; then
  REMOTE_CURL+=" --noproxy ${rendezvousIP}"
fi

while [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" != "200" ]]; do
  echo -n "."
  sleep 10;
done

echo
echo "Installing in progress..."
while 
  echo "-------------------------------"
  _status=$($REMOTE_CURL $assisted_rest)
  echo "$_status"| \
   jq -c '.[] | with_entries(select(.key | contains("name","updated_at","_count","status","validations_info")))|.validations_info|=(.// empty|fromjson|del(.. | .id?))'
  [[ "\"installing\"" != $(echo "$_status" |jq '.[].status') ]]
do sleep 15; done

echo
prev_percentage=""
echo "-------------------------------"
while
  total_percentage=$($REMOTE_CURL $assisted_rest |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    if [[ "$total_percentage" == "$prev_percentage" ]]; then
       echo -n "."
    else
      echo
      echo -n "Installation in progress: completed $total_percentage/100"
      prev_percentage=$total_percentage
    fi
  fi
  sleep 20;
  [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest)" == "200" ]]
do true; done
echo

echo "-------------------------------"
echo "Nodes Rebooted..."

duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."

sleep 30
send_command_to_all_hosts post_install

echo "Installation still in progress, oc command will be available soon, you can open another terminal to check the installation progress with oc commands..."
echo
echo "Waiting for the cluster to be ready..."
sleep 180
oc adm wait-for-stable-cluster
