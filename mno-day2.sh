#!/bin/bash
# 
# Helper script to apply the day2 operations
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
operators=$basedir/operators
manifests=$basedir/extra-manifests

config_file=$1;

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$basedir/instances/$cluster_name

day2_pp_templates=$manifests/day2/performance-profiles
day2_pp_workspace="$cluster_workspace"/day2/performance-profiles
day2_tuned_templates=$manifests/day2/tuned-profiles
day2_tuned_workspace="$cluster_workspace"/day2/tuned-profiles

mkdir -p $day2_pp_workspace
mkdir -p $day2_tuned_workspace

export KUBECONFIG=$cluster_workspace/auth/kubeconfig

oc get clusterversion
echo
oc get nodes
echo

ocp_release=$(oc version -o json|jq -r '.openshiftVersion')
ocp_y_version=$(echo $ocp_release | cut -d. -f 1-2)

function create_mcp_if_not_yet(){
  local name=$1
  local role=$2
  oc get mcp $name 1>/dev/null 2>/dev/null
  if [ $? == 1 ]; then
    cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: $name
  labels:
    machineconfiguration.openshift.io/role: "$name"
    pools.operator.machineconfiguration.openshift.io/$name: ""
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,$role]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/$1: ""
EOF
    info "mcp $name: select role $role" "created"
  fi
}

create_mcps_or_performance_profile(){
  local total_mcp=$(yq ".day2.mcp|length" $config_file)

  for ((i=0; i<$total_mcp; i++)); do
    mcp_name=$(yq ".day2.mcp[$i].name" "$config_file"|grep -vE '^null$')
    mcp_role=$(yq ".day2.mcp[$i].role" "$config_file"|grep -vE '^null$')
    if [[ -n "${mcp_name}" ]]; then
      create_mcp_if_not_yet "$mcp_name" "$mcp_role"
      #create performance profile for mcp
      if [[ "true" == $(yq ".day2.mcp[$i].performance_profile.enabled" "$config_file") ]]; then
        local file=$(yq ".day2.mcp[$i].performance_profile.manifest" "$config_file")
        if [[ "$file" =~ '.yaml.j2' ]]; then
          local yaml_file="${file%".yaml.j2"}-${mcp_name}.yaml"
          yq ".day2.mcp[$i]" "$config_file"|jinja2 "$day2_pp_templates/$file" > $day2_pp_workspace/${yaml_file}
          info "create performance profile: $day2_pp_workspace/${yaml_file}"
          oc apply -f "$day2_pp_workspace/${yaml_file}"
        elif [[ "$file" =~ '.yaml' ]]; then
           cp "$day2_pp_templates/$file" $day2_pp_workspace/${file}
           info "create performance profile: $day2_pp_workspace/${file}"
           oc apply -f $day2_pp_workspace/${file}
        fi
      fi

    fi
  done
}

create_tuned_profiles(){
  local total_tuneds=$(yq ".day2.tuned_profiles|length" $config_file)

  for ((i=0; i<$total_tuneds; i++)); do
    tuned_file=$(yq ".day2.tuned_profiles[$i]" "$config_file"|grep -vE '^null$')

    if [[ -n "${tuned_file}" ]]; then
      #absolate path
      if [[ "$tuned_file" = /* ]]; then
        tuned_file_abs=$tuned_file
      else
        tuned_file_abs=$day2_tuned_templates/$tuned_file
      fi
      if [ -f  $tuned_file_abs ]; then
        cp $tuned_file_abs $day2_tuned_workspace/$tuned_file
        info "create tuned profile: $day2_tuned_workspace/$tuned_file"
        oc apply -f $day2_tuned_workspace/$tuned_file
      fi
    fi
  done
}

apply_node_labels(){
  local total_master=$(yq '.hosts.masters|length' $config_file)

  for ((i=0; i<$total_master;i++)); do
    local node=$(yq ".hosts.masters[$i].hostname" "$config_file")
    readarray -t roles < <(yq ".hosts.masters[$i].roles[]" "$config_file")
    for ((r=0; r<${#roles[@]}; r++)); do
      local role="${roles[$r]}"
      if [[ $role =~ "=" ]]; then
        info "Role $node" "node-role.kubernetes.io/$role"
        oc label node "$node" "node-role.kubernetes.io/$role"
      else
        info "Role $node" "node-role.kubernetes.io/$role="
        oc label node "$node" "node-role.kubernetes.io/$role="
      fi
    done

    readarray -t labels < <(yq ".hosts.masters[$i].labels[]" "$config_file")
    for ((l=0; l<${#labels[@]}; l++)); do
      label="${labels[$l]}"
      info "Label $node" "$label"
      oc label node "$node" "$label"
    done
  done

  local total_worker=$(yq '.hosts.workers|length' $config_file)

  for ((i=0; i<$total_worker;i++)); do
    local node=$(yq ".hosts.workers[$i].hostname" "$config_file")
    readarray -t roles < <(yq ".hosts.workers[$i].roles[]" "$config_file")
    for ((r=0; r<${#roles[@]}; r++)); do
      local role="${roles[$r]}" 
      if [[ $role =~ "=" ]]; then
	      info "Role $node" "node-role.kubernetes.io/$role"
        oc label node "$node" "node-role.kubernetes.io/$role"
      else
	      info "Role $node" "node-role.kubernetes.io/$role="
        oc label node "$node" "node-role.kubernetes.io/$role="
      fi
    done

    readarray -t labels < <(yq ".hosts.workers[$i].labels[]" "$config_file")
    for ((l=0; l<${#labels[@]}; l++)); do
      label="${labels[$l]}"
      info "Label $node" "$label"
      oc label node "$node" "$label"
    done
  done
}

disable_operator_auto_upgrade(){
  subs=$(oc get subs -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}')
  subs=($subs)
  length=${#subs[@]}
  for i in $( seq 0 2 $((length-2)) ); do
    ns=${subs[$i]}
    name=${subs[$i+1]}
    info "operator $name auto upgrade:" "disabled"
    oc patch subscription -n $ns $name --type='json' -p=['{"op": "replace", "path": "/spec/installPlanApproval", "value":"Manual"}']
  done
}

config_day2_operators() {
  if [[ $(yq ".day2.operators" $config_file) != "null" ]]; then
    readarray -t keys < <(yq ".day2.operators|keys" $config_file|yq '.[]')
    for ((k=0; k<${#keys[@]}; k++)); do
      op_name="${keys[$k]}"
      op_desc=$(yq ".operators.$op_name.desc" $operators/operators.yaml)
      op_manifest=$manifests/day2/$op_name/
      op_workspace=$cluster_workspace/day2/${op_name}
      if [[ "true" == $(yq ".day1.operators.$op_name.enabled" $config_file) ]]; then
        info "$op_desc day2" "enabled"
        readarray -t files < <(find $op_manifest -type f -printf "%f\n")
        for ((i=0; i<${#files[@]}; i++)); do
          file="${files[$i]}"
          mkdir -p $op_workspace
          if [[ "$file" =~ '.yaml.j2' ]]; then
            local yaml_file=${file%".j2"}
            yq ".day2.operators.$op_name" "$config_file"|jinja2 "$op_manifest/$file" > $op_workspace/${yaml_file}
            oc apply -f $op_workspace/${yaml_file}
          elif [[ "$file" =~ '.yaml' ]]; then
             cp "$op_manifest/$file" $op_workspace/${file}
             oc apply -f "$op_workspace/$file"
          fi
          # todo add .sh and .sh.j2 support
        done
      else
        warn "${op_desc}" "disabled"
      fi
    done
  fi
}

echo
echo "------------------------------------------------"
echo "Applying day2 operations...."
echo

if [ "true" = "$(yq '.day2.node_labels_enabled' $config_file)" ]; then
  info "Node labels:" "enabled"
  apply_node_labels
else
  warn "Node labels:" "disable"
fi

master_schedulable(){
  if [[ "false" == "$(yq '.day2.masters_schedulable' $config_file)" ]]; then
    total_worker=$(yq '.hosts.workers|length' $config_file)
    if [[ $total_worker == 0 ]]; then
      warn "Compact cluster has mastersSchedulable enabled by default, cannot be disabled."
    else
      warn "Masters schedulable:" "no"
      oc patch schedulers.config.openshift.io/cluster --type merge -p '{"spec":{"mastersSchedulable":false}}'
    fi
  fi

  if [[ "true" == "$(yq '.day2.masters_schedulable' $config_file)" ]]; then
    warn "Masters schedulable:" "yes"
    oc patch schedulers.config.openshift.io/cluster --type merge -p '{"spec":{"mastersSchedulable":true}}'
  fi
}

echo
master_schedulable

echo
if [ "false" = "$(yq '.day2.disable_operator_auto_upgrade' $config_file)" ]; then
  warn "operator auto upgrade:" "enable"
else
  disable_operator_auto_upgrade
fi

create_mcps_or_performance_profile
create_tuned_profiles

echo
config_day2_operators

echo

echo
echo "Done."
