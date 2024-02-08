#!/bin/bash
# 
# Helper script to generate bootable ISO with OpenShift agent based installer
# usage: ./mno-iso.sh -h
# 


if ! type "yq" > /dev/null; then
  echo "Cannot find yq in the path, please install yq on the node first. ref: https://github.com/mikefarah/yq#install"
fi

if ! type "jinja2" > /dev/null; then
  echo "Cannot find jinja2 in the path, will install it with pip3 install jinja2-cli and pip3 install jinja2-cli[yaml]"
  pip3 install --user jinja2-cli
  pip3 install --user jinja2-cli[yaml]
fi

info(){
  printf  $(tput setaf 2)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

warn(){
  printf  $(tput setaf 3)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}


usage(){
	info "Usage: $0 [config file] [ocp version]"
  info "config file and ocp version are optional, examples:"
  info "- $0 mno130.yaml" " equals: $0 mno130.yaml stable-4.12"
  info "- $0 mno130.yaml 4.12.10"
  echo 
  info "Prepare a configuration file by following the example in config.yaml.sample"
  echo "-----------------------------------"
  echo "# content of config.yaml.sample"
  cat config.yaml.sample
  echo
  echo "-----------------------------------"
  echo
  info "Example to run it: $0 config-mno130.yaml"
  echo
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
templates=$basedir/templates
operators=$basedir/operators

config_file=$1; shift
ocp_release=$1; shift

if [ -z "$config_file" ]
then
  config_file=config.yaml
fi

if [ -z "$ocp_release" ]
then
  ocp_release='stable-4.12'
fi

ocp_release_version=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release}/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')

#if release not available on mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/, probably ec (early candidate) version.
if [ -z $ocp_release_version ]; then
  ocp_release_version=$ocp_release
fi

export ocp_y_release=$(echo $ocp_release_version |cut -d. -f1-2)

echo "You are going to download OpenShift installer $ocp_release: ${ocp_release_version}"

if [ -f $basedir/openshift-install-linux.tar.gz ]; then
  rm -f $basedir/openshift-install-linux.tar.gz
fi

status_code=$(curl -s -o /dev/null -w "%{http_code}" https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$ocp_release_version/)
if [ $status_code = "200" ]; then
  curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release_version}/openshift-install-linux.tar.gz -o $basedir/openshift-install-linux.tar.gz
  tar xfz $basedir/openshift-install-linux.tar.gz openshift-install
else
  #fetch from image
  oc adm release extract --command=openshift-install quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64 --registry-config=$(yq '.pull_secret' $config_file)
fi

cluster_name=$(yq '.cluster.name' $config_file)
cluster_workspace=$basedir/$cluster_name

mkdir -p $cluster_workspace
mkdir -p $cluster_workspace/openshift

echo

enable_crun(){
  if [ "4.12" = $ocp_y_release ]; then
    warn "Container runtime crun(4.13+):" "disabled"
  else
    #4.13+ by default enabled.
    if [ "false" = "$(yq '.day1.crun' $config_file)" ]; then
      warn "Container runtime crun(4.13+):" "disabled"
    else
      info "Container runtime crun(4.13+):" "enabled"
      cp $templates/day1/crun/*.yaml $cluster_workspace/openshift/
    fi
  fi
}


install_operators(){
  if [[ $(yq '.day1.operators' $config_file) != "null" ]]; then
    readarray -t keys < <(yq ".day1.operators|keys" $config_file|yq '.[]')
    for ((k=0; k<${#keys[@]}; k++)); do
      key="${keys[$k]}"
      desc=$(yq ".operators.$key.desc" $operators/operators.yaml)
      if [[ "true" == $(yq ".day1.operators.$key" $config_file) ]]; then
        info "$desc" "enabled"
        cp $operators/$key/*.yaml $cluster_workspace/openshift/

        #render j2 files
        j2files=$(ls $operators/$key/*.j2 2>/dev/null)
        for f in $j2files; do
          tname=$(basename $f)
          fname=${tname//.j2/}
          jinja2 $f > $cluster_workspace/openshift/$fname
        done
      else
        warn "$desc" "disabled"
      fi
    done
  fi
}

apply_extra_manifests(){
  if [ -d $basedir/extra-manifests ]; then
    echo "Copy customized CRs from extra-manifests folder if present"
    echo "$(ls -l $basedir/extra-manifests/)"
    cp $basedir/extra-manifests/day1/*.yaml $cluster_workspace/openshift/ 2>/dev/null

    #render j2 files
    j2files=$(ls $basedir/extra-manifests/day1/*.j2 2>/dev/null)
    for f in $j2files; do
      tname=$(basename $f)
      fname=${tname//.j2/}
      jinja2 $f > $cluster_workspace/openshift/$fname
    done

  fi
}

enable_crun
install_operators
apply_extra_manifests

pull_secret=$(yq '.pull_secret' $config_file)
export pull_secret=$(cat $pull_secret)
ssh_key=$(yq '.ssh_key' $config_file)
export ssh_key=$(cat $ssh_key)

bundle_file=$(yq '.additional_trust_bundle' $config_file)
if [[ "null" != "$bundle_file" ]]; then
  export additional_trust_bundle=$(cat $bundle_file)
fi

jinja2 $templates/agent-config.yaml.j2 $config_file > $cluster_workspace/agent-config.yaml
jinja2 $templates/install-config.yaml.j2 $config_file > $cluster_workspace/install-config.yaml

cp $cluster_workspace/agent-config.yaml $cluster_workspace/agent-config.backup.yaml
cp $cluster_workspace/install-config.yaml $cluster_workspace/install-config.backup.yaml

echo
echo "Generating boot image..."
echo
$basedir/openshift-install --dir $cluster_workspace agent --log-level info create image

echo ""
echo "------------------------------------------------"
echo "kubeconfig: $cluster_workspace/auth/kubeconfig."
echo "kubeadmin password: $cluster_workspace/auth/kubeadmin-password."
echo "------------------------------------------------"

echo
echo "Next step: Go to your BMC console and boot the node from ISO: $cluster_workspace/agent.x86_64.iso."
echo "You can also run ./mno-install.sh to boot the node from the image automatically if you have a HTTP server serves the image."
echo "Enjoy!"
