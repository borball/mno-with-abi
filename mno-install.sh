#!/bin/bash
# Helper script to boot the node via redfish API from the ISO image
# usage: ./mno-install.sh cluster 
#

set -x

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

show_info(){
  printf  $(tput setaf 2)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

show_warn(){
  printf  $(tput setaf 3)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

usage(){
  echo "Usage : $0 <cluster-name>"
  echo "If <cluster-name> is not present, it will install the newest cluster created by mno-iso.sh"
  echo "Example : $0" 
  echo "Example : $0 mno130" 
}

if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then 
  usage
  exit
fi

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
cluster_name=$1; shift

if [ -z "$cluster_name" ]; then
  cluster_name=$(ls -t $basedir/instances |head -1)
  if [ -z "$cluster_name" ]; then
    echo "No cluster found in $basedir/instances"
    exit
  fi
fi

set -euoE pipefail
set -o nounset

cluster_workspace=$basedir/instances/$cluster_name

config_file=$cluster_workspace/config-resolved.yaml
if [ -f "$config_file" ]; then
  echo "Will install cluster $cluster_name with config: $config_file"
else
  "Config file $config_file not exist, please check."
  exit -1
fi

total_master=$(yq '.hosts.masters|length' $config_file)
iso_image=$(yq '.iso.address' $config_file)
deploy_cmd=$(eval echo $(yq '.iso.deploy // ""' $config_file))

domain_name=$(yq '.cluster.domain' $config_file)
api_fqdn="api."$cluster_name"."$domain_name
api_token=$(jq -r '.["*gencrypto.AuthConfig"].AgentAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
if [[ -z "${api_token}" ]]; then
  api_token=$(jq -r '.["*gencrypto.AuthConfig"].UserAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
fi

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

send_command_to_all_hosts(){
  command=$1
  bmc_noproxy=$(yq ".hosts.common.bmc.bypass_proxy" $config_file)

  for ((i=0; i<$total_master;i++)); do
    bmc_address=$(yq ".hosts.masters[$i].bmc.address" $config_file)
    bmc_userpass=$(yq ".hosts.masters[$i].bmc.password" $config_file)
    bmc_uuid=$(yq -r ".hosts.masters[$i].bmc.node_uuid" $config_file)
    echo "** Master $i [${bmc_address},${bmc_userpass},${bmc_uuid}]: $cluster_workspace/boot_master_$i.log"
    boot_option="-l $cluster_workspace/boot_master_$i.log"
    if [[ "true" == "${bmc_noproxy}" ]]; then
      boot_option+=" -n"
    fi
    $basedir/node-boot.sh -c $command -n -h ${bmc_address} -u ${bmc_userpass} -i ${iso_image} ${bmc_uuid:+"-k$bmc_uuid"} $boot_option
    echo ""
  done

  if [ ! -z "$(yq '.hosts.workers' $config_file)" ]; then
    total_worker=$(yq '.hosts.workers|length' $config_file)
    for ((i=0; i<$total_worker;i++)); do
      bmc_address=$(yq ".hosts.workers[$i].bmc.address" $config_file)
      bmc_userpass=$(yq ".hosts.workers[$i].bmc.password" $config_file)
      bmc_uuid=$(yq -r ".hosts.workers[$i].bmc.node_uuid" $config_file)
      echo "** Worker $i [${bmc_address},${bmc_userpass},${bmc_uuid}]: $cluster_workspace/boot_worker_$i.log"
      boot_option="-l $cluster_workspace/boot_worker_$i.log"
      if [[ "true" == "${bmc_noproxy}" ]]; then
        boot_option+=" -n"
      fi
      $basedir/node-boot.sh -c $command -n -h ${bmc_address} -u ${bmc_userpass} -i ${iso_image} ${bmc_uuid:+"-k$bmc_uuid"} $boot_option
      echo ""
    done
  fi

}

deploy_iso(){
  [[ -z "$deploy_cmd" ]] && return
  [[ ! -x $(realpath $deploy_cmd) ]] && echo "Failed to deploy ISO, command not executable: $deploy_cmd" && exit
  echo "Deploy ISO: $deploy_cmd $cluster_workspace/agent.x86_64.iso $iso_image"
  $deploy_cmd $cluster_workspace/agent.x86_64.iso $iso_image
  local result=$?
  if [[ $result -ne 0 ]]; then
    echo "Failed: $result"
    exit
  fi
}

wait_for_stable_cluster(){
  local interval=${1:-60}
  local next_run=0
  local skipped=""
  set +e
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local current=$(date +%s --date="now")
    if [[ $current -gt $next_run ]]; then
      if [[ ! -z "$skipped" ]]; then
        echo
        skipped=""
      fi
      echo $line
      let next_run=$current+$interval
     else
       echo -n .
       skipped="$line"
     fi
  done < <(oc adm wait-for-stable-cluster --minimum-stable-period=5m  2>&1)
  set -e
  if [[ ! -z "$skipped" ]]; then
    echo
    echo $skipped
  fi
}

approve_pending_install_plans(){
  echo "Approve pending approval InstallPlans if have, will repeat 5 times."
  for i in {1..5}; do
    echo "checking $i"
    oc get ip -A
    while read -s IP; do
      echo "oc patch $IP --type merge --patch '{"spec":{"approved":true}}'"
      oc patch $IP --type merge --patch '{"spec":{"approved":true}}'
   done < <(oc get sub -A -o json |\
     jq -r '.items[]|select( (.spec.startingCSV != null) and (.status.installedCSV == null) and (.status.installPlanRef != null))|.status.installPlanRef|"-n \(.namespace) ip \(.name)"')

    if [[ 0 ==  $(oc get sub -A -o json|jq '[.items[]|select(.status.installedCSV==null)]|length') ]]; then
      echo
      break
    fi

    sleep 30
    echo
  done

  echo "All operator versions:"
  oc get csv -A -o custom-columns="0AME:.metadata.name,DISPLAY:.spec.displayName,VERSION:.spec.version" |sort -f|uniq|sed 's/0AME/NAME/'
}

echo "-------------------------------"
deploy_iso

SECONDS=0
echo ""
echo "-------------------------------"
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

if [[ ! -z "${api_token}" ]]; then
  REMOTE_CURL+=" -H 'Authorization: ${api_token}'"
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
wait_for_stable_cluster 60

approve_pending_install_plans
echo
echo "You are all set..."
