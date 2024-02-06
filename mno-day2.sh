#!/bin/bash
# 
# Helper script to apply the day2 operations on SNO node
# Usage: ./mno-day2.sh config.yaml
#

if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

usage(){
	echo "Usage: $0 [config.yaml]"
  echo "Example: $0 config-compact.yaml"
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


info(){
  printf  $(tput setaf 2)"%-60s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-60s %-10s"$(tput sgr0)"\n" "$@"
}

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
templates=$basedir/templates

config_file=$1;

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$cluster_name
export KUBECONFIG=$cluster_workspace/auth/kubeconfig

oc get clusterversion
echo
oc get nodes
echo

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)

echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo

function create_mcp(){
  local role=$1
  oc get mcp $role 1>/dev/null 2>/dev/null
  if [ $? == 1 ]; then
    cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: $1
  labels:
    machineconfiguration.openshift.io/role: "$1"
    pools.operator.machineconfiguration.openshift.io/$1: ""
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,$1]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/$1: ""
EOF
    info "mcp $role" "created"
  fi
}

add_node_label(){
  oc label node $1 $2
}

apply_node_labels(){
  local total_master=$(yq '.hosts.masters|length' $config_file)

  for ((i=0; i<$total_master;i++)); do
    local node=$(yq ".hosts.masters[$i].hostname" "$config_file")
    readarray roles < <(yq ".hosts.masters[$i].roles[]" "$config_file")
    if [[ -n "$roles" ]]; then
      for role in $roles; do
        create_mcp "$role"
        oc label node "$node" "node-role.kubernetes.io/$role="
      done
    fi

    readarray labels < <(yq ".hosts.masters[$i].labels[]" "$config_file")
    if [[ -n "$labels" ]]; then
      for label in $labels; do
        oc label node $node $label
      done
    fi
  done

  local total_worker=$(yq '.hosts.workers|length' $config_file)

  for ((i=0; i<$total_worker;i++)); do
    readarray roles < <(yq ".hosts.workers[$i].roles[]" "$config_file")
    for role in $roles; do
      create_mcp "$role"
      oc label node "$node" "node-role.kubernetes.io/$role="
    done

    readarray labels < <(yq ".hosts.workers[$i].labels[]" "$config_file")
    if [[ -n "$labels" ]]; then
      for label in $labels; do
        oc label node $node $label
      done
    fi
  done
}

apply_node_labels

echo

echo
echo "Done."
