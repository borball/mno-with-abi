#!/bin/bash
# Helper script to fetch disk information from the node


if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

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
cluster_workspace=$basedir/instances/$cluster_name
config_file=$cluster_workspace/config-resolved.yaml

if [[ ! -f ${config_file} ]]; then
  echo "cluster config file not found:${config_file}"
  exit
fi

fetch_disk_info() {
  local SSH="ssh -q -oStrictHostKeyChecking=no"
  local remote_user="core"
  local remote_host=$1
  echo =====================================================
  echo "${remote_host}"
  $SSH ${remote_user}@${remote_host} hostnamectl
  echo ""
  $SSH ${remote_user}@${remote_host} dmesg |egrep -E 'Attached .* disk|nvme nvme.* pci.*'
  echo ""
  $SSH ${remote_user}@${remote_host} lsblk -p
  echo ""
  while read disk; do
    echo "udevadm info $disk"
    $SSH ${remote_user}@${remote_host} sudo udevadm info $disk  
    echo ""
  done < <($SSH ${remote_user}@${remote_host} -q lsblk -d -p -n -oNAME | grep -E 'sd|nvme'|sort)
}

total_master=$(yq '.hosts.masters|length' $config_file)
for ((i=0; i<$total_master;i++)); do
  node_hostname=$(yq ".hosts.masters[$i].hostname" $config_file)
  fetch_disk_info $node_hostname
done

if [ ! -z "$(yq '.hosts.workers' $config_file)" ]; then
  total_worker=$(yq '.hosts.workers|length' $config_file)
  for ((i=0; i<$total_worker;i++)); do
    node_hostname=$(yq ".hosts.workers[$i].hostname" $config_file)
    fetch_disk_info $node_hostname
  done
fi
