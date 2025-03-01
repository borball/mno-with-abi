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

config_file_input=$1; shift
ocp_release=$1; shift

if [ -z "$config_file_input" ]
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
export OCP_Y_VERSION=$ocp_y_release
export OCP_Z_VERSION=$ocp_release_version

cluster_name=$(yq '.cluster.name' $config_file_input)
cluster_workspace=$basedir/instances/$cluster_name

if [[ -d "${cluster_workspace}" ]]; then
  echo "${cluster_workspace} already exists, please delete the folder ${cluster_workspace} and re-run the script."
  exit -1
fi

mkdir -p $cluster_workspace
mkdir -p $cluster_workspace/openshift

config_file="$cluster_workspace/config-resolved.yaml"

if [ $(cat $config_file_input |grep -E 'OCP_Y_RELEASE|OCP_Z_RELEASE' |wc -l) -gt 0 ]; then
  sed "s/OCP_Y_RELEASE/$ocp_y_release/g;s/OCP_Z_RELEASE/$ocp_release_version/g" $config_file_input > $config_file
else
  cp $config_file_input $config_file
fi
echo "Will use $config_file as the configuration in other mno-* scripts."

if [ ! -f $basedir/openshift-install-linux.$ocp_release_version.tar.gz ]; then
  echo "You are going to download OpenShift installer $ocp_release: ${ocp_release_version}"
  echo
  status_code=$(curl -s -o /dev/null -w "%{http_code}" https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$ocp_release_version/)
  if [ $status_code = "200" ]; then
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_release_version}/openshift-install-linux.tar.gz -o $basedir/openshift-install-linux.$ocp_release_version.tar.gz
    if [[ $? -eq 0 ]]; then
      tar zxf $basedir/openshift-install-linux.$ocp_release_version.tar.gz -C $basedir openshift-install
    else
      rm -f $basedir/openshift-install-linux.$ocp_release_version.tar.gz
      exit -1
    fi
  else
    #fetch from image
    if [[ $ocp_release == *"nightly"* ]] || [[ $ocp_release == *"ci"* ]]; then
      oc adm release extract --command=openshift-install registry.ci.openshift.org/ocp/release:$ocp_release_version --registry-config=$(yq '.pull_secret' $config_file) --to="$basedir"
    else
      oc adm release extract --command=openshift-install quay.io/openshift-release-dev/ocp-release:$ocp_release_version-x86_64 --registry-config=$(yq '.pull_secret' $config_file) --to="$basedir"
    fi
  fi
else
  tar zxf $basedir/openshift-install-linux.$ocp_release_version.tar.gz -C $basedir openshift-install
fi

enable_crun(){
  if [ "4.12" = $ocp_y_release ]; then
    warn "Container runtime crun(4.12):" "disabled"
  else
    if [ "4.13" = $ocp_y_release ] || [ "4.14" = $ocp_y_release ] || [ "4.15" = $ocp_y_release ] || [ "4.16" = $ocp_y_release ] || [ "4.17" = $ocp_y_release ]; then
      #4.13+ by default enabled.
      if [ "false" = "$(yq '.day1.crun' $config_file)" ]; then
        warn "Container runtime crun(4.13-4.17):" "disabled"
      else
        info "Container runtime crun(4.13-4.17):" "enabled"
        cp $templates/day1/crun/*.yaml $cluster_workspace/openshift/
      fi
    else
      info "Container runtime crun(4.18+):" "default"
    fi
  fi
}


install_operators(){
  if [[ $(yq '.day1.operators' $config_file) != "null" ]]; then
    readarray -t keys < <(yq ".day1.operators|keys" $config_file|yq '.[]')
    for ((k=0; k<${#keys[@]}; k++)); do
      key="${keys[$k]}"
      desc=$(yq ".operators.$key.desc" $operators/operators.yaml)
      if [[ "true" == $(yq ".day1.operators.$key.enabled" $config_file) ]]; then
        info "$desc" "enabled"
        cp $operators/$key/*.yaml $cluster_workspace/openshift/ 2>/dev/null

        #render j2 files
        j2files=$(ls $operators/$key/*.j2 2>/dev/null)
        for f in $j2files; do
          tname=$(basename $f)
          fname=${tname//.j2/}
          yq ".day1.operators.$key" $config_file| jinja2 $f > $cluster_workspace/openshift/$fname
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
    find $basedir/extra-manifests/day1/ -type f \( -name "*.yaml" -o -name "*.yaml.j2" \) -printf ' - %P\n'
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

operator_catalog_sources(){
  if [ "4.12" = $ocp_y_release ] || [ "4.13" = $ocp_y_release ] || [ "4.14" = $ocp_y_release ] || [ "4.15" = $ocp_y_release ]; then
    if [[ $(yq '.container_registry' $config_file) != "null" ]]; then
      jinja2 $templates/day1/operatorhub.yaml.j2 $config_file > $cluster_workspace/openshift/operatorhub.yaml
    fi
  else
    #4.16+, disable marketplace operator
    cp $templates/day1/marketplace/09-openshift-marketplace-ns.yaml $cluster_workspace/openshift/

    #create unmanaged catalog sources
    if [[ "$(yq '.container_registry.catalog_sources.defaults' $config_file)" != "null" ]]; then
      #enable the ones in container_registry.catalog_sources.defaults
      local size=$(yq '.container_registry.catalog_sources.defaults|length' $config_file)
      for ((k=0; k<$size; k++)); do
        local name=$(yq ".container_registry.catalog_sources.defaults[$k]" $config_file)
        jinja2 $templates/day1/catalogsource/$name.yaml.j2 > $cluster_workspace/openshift/$name.yaml
      done
    else
      #by default redhat-operators and certified-operators shall be enabled
      jinja2 $templates/day1/catalogsource/redhat-operators.yaml.j2 > $cluster_workspace/openshift/redhat-operators.yaml
      jinja2 $templates/day1/catalogsource/certified-operators.yaml.j2 > $cluster_workspace/openshift/certified-operators.yaml
    fi

  fi

  #all versions
  if [ "$(yq '.container_registry.catalog_sources.customs' $config_file)" != "null" ]; then
    local size=$(yq '.container_registry.catalog_sources.customs|length' $config_file)
    for ((k=0; k<$size; k++)); do
      yq ".container_registry.catalog_sources.customs[$k]" $config_file |jinja2 $templates/day1/catalogsource/catalogsource.yaml.j2 > $cluster_workspace/openshift/catalogsource-$k.yaml
    done
  fi

  #all versions
  if [ "$(yq '.container_registry.icsp' $config_file)" != "null" ]; then
    local size=$(yq '.container_registry.icsp|length' $config_file)
    for ((k=0; k<$size; k++)); do
      local name=$(yq ".container_registry.icsp[$k]" $config_file)
      if [ -f "$name" ]; then
        info "$name" "copy to $cluster_workspace/openshift/"
        cp $name $cluster_workspace/openshift/
      else
        warn "$name" "not a file or not exist"
      fi
    done
  fi
}

operator_catalog_sources
enable_crun
install_operators
apply_extra_manifests

pull_secret=$(yq '.pull_secret' $config_file)
export pull_secret=$(cat $pull_secret)
ssh_key=$(yq '.ssh_key' $config_file)
if [[ -z "$ssh_key" ]] || [[ ! -f "$ssh_key" ]]; then
  warn "ssh-key" "ssh_key not set or file missing"
  exit -1
fi
export ssh_key=$(cat $ssh_key)

bundle_file=$(yq '.additional_trust_bundle' $config_file)
if [[ "null" != "$bundle_file" ]]; then
  export additional_trust_bundle=$(cat $bundle_file)
fi

jinja2 $templates/agent-config.yaml.j2 $config_file > $cluster_workspace/agent-config.yaml
jinja2 $templates/install-config.yaml.j2 $config_file > $cluster_workspace/install-config.yaml

mirror_source=$(yq '.container_registry.image_source' $config_file)
if [[ "null" != "$mirror_source" ]]; then
  cat $mirror_source >> $cluster_workspace/install-config.yaml
fi

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
