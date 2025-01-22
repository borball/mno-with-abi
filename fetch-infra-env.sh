#!/bin/bash
# Helper script to fetch infra-env from assisted-installer
# usage: ./fetch-infra-env.sh
# usage: ./fetch-infor-env <cluster-name>
#
# based on https://github.com/openshift/assisted-service/tree/master/docs/user-guide/samples

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi


usage(){
  echo "Usage : $0"
  echo "Usage : $0 <cluster_name>"
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
fi

cluster_workspace=$basedir/instances/$cluster_name

config_file=$cluster_workspace/config-resolved.yaml
if [ -f "$config_file" ]; then
  echo "Will access cluster $cluster_name with config: $config_file"
else
  "Config file $config_file not exist, please check."
  exit -1
fi

ipv4_enabled=$(yq '.hosts.common.ipv4.enabled // "" ' $config_file)
if [ "true" = "$ipv4_enabled" ]; then
  rendezvousIP=$(yq '.hosts.masters[0].ipv4.ip' $config_file)
  assisted_rest=http://$rendezvousIP:8090
else
  rendezvousIP=$(yq '.hosts.masters[0].ipv6.ip' $config_file)
  assisted_rest=http://[$rendezvousIP]:8090
fi

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

api_token=$(jq -r '.["*gencrypto.AuthConfig"].AgentAuthToken // empty' $cluster_workspace/.openshift_install_state.json)
bmc_noproxy=$(yq ".hosts.common.bmc.bypass_proxy" $config_file)

REMOTE_CURL="curl -s"
if [[ "true"=="${bmc_noproxy}" ]]; then
  REMOTE_CURL+=" --noproxy ${rendezvousIP}"
fi

if [[ ! -z "${api_token}" ]]; then
  REMOTE_CURL+=" -H 'Authorization: ${api_token}'"
fi

echo "-------------------------------"

echo "Waiting for Assisted Installer..."
# first wait for 200 response code
while [[ "$($REMOTE_CURL -o /dev/null -w ''%{http_code}'' $assisted_rest/api/assisted-install/v2/clusters)" != "200" ]]; do
  echo -n "."
  sleep 10;
done

# now wait till cluster_id become avaiable
while
  cluster_href=$($REMOTE_CURL $assisted_rest/api/assisted-install/v2/clusters|jq -r '.[0].href')
  [[ "$cluster_href" == "null" ]]
do
  echo -n "."
  sleep 10;
done
echo

cluster_id=$(echo ${cluster_href}|rev|cut -f 1 -d / |rev)
output="${cluster_workspace}/assisted-env-${cluster_id}"
echo "Output directory: ${output}"
mkdir -p ${output}
# TODO should we wait till it's ready to install?
echo "Saving ${output}/cluster.json"
$REMOTE_CURL $assisted_rest${cluster_href} > ${output}/cluster.json
echo "Saving ${output}/hosts.json"
$REMOTE_CURL "$assisted_rest${cluster_href}/hosts" > ${output}/hosts.json

while read -r host_href; do
  id=$(echo ${host_href}|rev|cut -f 1 -d / | rev)
  echo "Saving ${output}/infra_envs.${id}.json"
  $REMOTE_CURL "$assisted_rest${host_href}" > ${output}/infra_envs.${id}.json
  echo "==> Parsing to ${output}/infra_envs.${id}.parsed.json"
  jq \
  'def convert_json(key): key|=(.// empty|fromjson);
  .| convert_json(.ntp_sources)
   | convert_json(.domain_name_resolutions)
   | convert_json(.disks_info)
   | convert_json(.images_status)
   | convert_json(.validations_info)
   | convert_json(.inventory)' \
    ${output}/infra_envs.${id}.json > ${output}/infra_envs.${id}.parsed.json
done < <(jq -r '.[]|.href' ${output}/hosts.json)
