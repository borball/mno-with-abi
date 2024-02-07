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
operators=$basedir/operators
manifests=$basedir/extra-manifests

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

function create_mcp(){
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

create_mcps(){
  local total_mcp=$(yq ".day2.mcp|length" $config_file)

  for ((i=0; i<$total_mcp; i++)); do
    mcp_name=$(yq ".day2.mcp[$i].name" "$config_file"|grep -vE '^null$')
    mcp_role=$(yq ".day2.mcp[$i].role" "$config_file"|grep -vE '^null$')
    if [[ -n "${mcp_name}" ]]; then
      create_mcp "$mcp_name" "$mcp_role"

      #create performance profile for mcp
      if [[ "true" == $(yq ".day2.mcp[$i].performance_profile.enabled" "$config_file") ]]; then
        local day2_performance_profiles=$cluster_workspace/day2/performance_profiles
        mkdir -p $day2_performance_profiles
        local file=$(yq ".day2.mcp[$i].performance_profile.manifest" "$config_file")
        if [[ "$file" =~ '.yaml.j2' ]]; then
          local yaml_file=${file%".j2"}
          yq ".day2.mcp[$i]" "$config_file"|jinja2 "$manifests/day2/performance_profiles/$file" > $day2_performance_profiles/${yaml_file}
          oc apply -f $day2_performance_profiles/${yaml_file}
        elif [[ "$file" =~ '.yaml' ]]; then
           cp "$manifests/day2/performance_profiles/$file" $day2_performance_profiles/${file}
           oc apply -f $day2_performance_profiles/${file}
        fi
      fi

    fi
  done
}

create_performance_profiles(){
  local total_pp=$(yq ".day2.performance_profiles|length" $config_file)

  for ((i=0; i<$total_pp; i++)); do
    pp_file=$(yq ".day2.performance_profiles[$i]" "$config_file"|grep -vE '^null$')

    if [[ -n "${pp_file}" ]]; then
      #absolate path
      if [[ "$pp_file" = /* ]]; then
        pp_file_abs=$pp_file
      else
        pp_file_abs=$manifests/day2/performance_profiles/$pp_file
      fi
      if [ -f  $pp_file_abs ]; then
        info "create performance profile: $pp_file_abs"
        oc apply -f $pp_file_abs
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
        tuned_file_abs=$manifests/day2/tuned_profiles/$tuned_file
      fi
      if [ -f  $tuned_file_abs ]; then
        info "create tuned profile: $tuned_file_abs"
        oc apply -f $tuned_file_abs
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
      if [[ "true" == $(yq ".day1.operators.$op_name" $config_file) ]]; then
        info "$op_desc day2" "enabled"
        mkdir -p $cluster_workspace/day2/
        readarray -t files < <(find $manifests/day2/$op_name/ -type f -printf "%f\n")
        for ((i=0; i<${#files[@]}; i++)); do
          file="${files[$i]}"
          mkdir -p $cluster_workspace/day2/${op_name}
          if [[ "$file" =~ '.yaml.j2' ]]; then
            local yaml_file=${file%".j2"}
            yq ".operators.$op_name" "$config_file"|jinja2 "$manifests/day2/$op_name/$file" > $cluster_workspace/day2/${op_name}/${yaml_file}
            oc apply -f $cluster_workspace/day2/${op_name}/${yaml_file}
          elif [[ "$file" =~ '.yaml' ]]; then
             cp "$manifests/day2/$op_name/$file" $cluster_workspace/day2/${op_name}/${yaml_file}
             oc apply -f "$cluster_workspace/day2/${op_name}/$file"
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
  info "node labels:" "enabled"
  apply_node_labels
else
  warn "node labels:" "disable"
fi

if [ "false" = "$(yq '.day2.disable_operator_auto_upgrade' $config_file)" ]; then
  warn "operator auto upgrade:" "enable"
else
  disable_operator_auto_upgrade
fi

create_mcps
create_performance_profiles
create_tuned_profiles
config_day2_operators

echo

echo
echo "Done."
