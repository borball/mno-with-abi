#!/bin/bash

OCP_RELEASE=${1}
LOCAL_REGISTRY="registry.service.local:5000"
LOCAL_REPOSITORY="operators"
PRODUCT_REPO="redhat"
LOCAL_SECRET_JSON="./pull-secret.json"
RELEASE_NAME="ocp-release"
ARCHITECTURE="x86_64"

if [[ -z "${OCP_RELEASE}" ]]; then
  echo "Usage: ${0} <OCP_REALASE> [docker|podman]"
  echo ""
  echo "Example: ${0} 4.12.33 docker"
  exit 0
fi

if [[ "$LOCAL_REPOSITORY" =~ "/" ]]; then
  echo "LOCAL_REPOSITORY must be single folder for oc adm catlog mirror: '$LOCAL_REPOSITORY'"
  echo "or adjust --max-components=n in the script to allow it"
  exit -1
fi

OPERATOR_RELEASE=$(echo "${OCP_RELEASE}" |cut -f 1-2 -d .)
# TODO, calculate dependency use jq -r '.. .packageName? // empty' index.json |sort|uniq
OPERATOR_LIST=(
  "odf-operator"
  "odf-csi-addons-operator"
  "ocs-operator"
  "mcg-operator"
  "local-storage-operator"
  "sriov-network-operator"
  "kubernetes-nmstate-operator"
  "ptp-operator"
  "sriov-fec"
  "metallb-operator"
  "cluster-logging")

# build the jq/yq expression to select entry with either name or package in the OPERATOR_LIST
filter_expression() {
  echo -n ".| select ( ["
  total=${#OPERATOR_LIST[@]}
  for (( i=0; i<${total}; i++ )); do
    if [[ $i -gt 0 ]]; then
      echo -n ","
    fi
    echo -n "\"${OPERATOR_LIST[$i]}\""
  done
  echo -n "] - [.name,.package]|length < $total)"
}

# https://docs.openshift.com/container-platform/4.12/operators/admin/olm-managing-custom-catalogs.html#olm-filtering-fbc_olm-managing-custom-catalogs
BUILD_DIR=operators/${OPERATOR_RELEASE}

cmd=$2
if [[ -z "$cmd" ]]; then
  if command -v podman > /dev/null; then
    echo "## command podman is used"
    cmd="podman"
  elif command -v docker > /dev/null; then
    echo "## command docker is used"
    cmd="docker"
  else
    echo "## No command found to process docker images"
    exit 1
  fi
fi

mirrorOperators() {
  local CATALOG_SRC="$1"
  local CATALOG_DIR="${BUILD_DIR}/${CATALOG_SRC}"
  local DOCKER_CONFIG_DIR="./auth"
  # see https://docs.openshift.com/container-platform/4.12/cli_reference/opm/cli-opm-install.html
  # https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest-${OPERATOR_RELEASE}/opm-linux.tar.gz
  printf  $(tput setaf 2)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" \
	  "Destination: ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE}"
  mkdir -p "${CATALOG_DIR}"
  if [[ ! -f "${CATALOG_DIR}.Dockerfile" ]]; then
    echo "$(date -u) Generator ${CATALOG_DIR}.Dockerfile"
    # DO NOT USE ORIGINAL OPREATOR INDEX unless we are only adding new operators
    opm generate dockerfile ${CATALOG_DIR}
    if [[ $? -ne 0 ]] ; then
      printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
      exit -1
    fi
  fi

  # Check if we need to render the index again
  if [[ $(jq '.schema' "${CATALOG_DIR}.json" 2>/dev/null|wc -l) -lt 1 ]]; then
    echo "$(date -u) Extract the index.json from registry.redhat.io/${PRODUCT_REPO}/${CATALOG_SRC}:v${OPERATOR_RELEASE}"
    [[ -d "${DOCKER_CONFIG_DIR}" ]] || mkdir -p "${DOCKER_CONFIG_DIR}"
    cp -u "${LOCAL_SECRET_JSON}" ${DOCKER_CONFIG_DIR}/config.json
    DOCKER_CONFIG=${DOCKER_CONFIG_DIR} opm render registry.redhat.io/${PRODUCT_REPO}/${CATALOG_SRC}:v${OPERATOR_RELEASE} -o json > "${CATALOG_DIR}.json"
    if [[ $? -ne 0 ]] ; then
      printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
      exit -1
    fi
  fi

  echo "$(date -u) Filter ${CATALOG_DIR}.json"
  jq -M "$(filter_expression)" "${CATALOG_DIR}.json" > "${CATALOG_DIR}/index.json"
  if [[ $? -ne 0 ]] ; then
    printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
    exit -1
  fi

  echo "$(date -u) Validate ${CATALOG_DIR}"
  opm validate "${CATALOG_DIR}"
  if [[ $? -ne 0 ]] ; then
    printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
    exit -1
  fi

  echo "$(date -u) Build container image ${CATALOG_DIR}.Dockerfile"
  ${cmd} build ${BUILD_DIR} -f ${CATALOG_DIR}.Dockerfile \
      -t "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE}"
  if [[ $? -ne 0 ]] ; then
    printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
    exit -1
  fi

  echo "$(date -u) Push container image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE}"
  ${cmd} push ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE}
  if [[ $? -ne 0 ]] ; then
    printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
    exit -1
  fi

  # mirror based on the pruned index
  echo "$(date -u) Mirroring operator images from ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE}"
  oc adm catalog mirror ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/${CATALOG_SRC}:v${OPERATOR_RELEASE} \
    "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}" \
    --to-manifests="${BUILD_DIR}/manifests/${CATALOG_SRC}" \
    --max-per-registry=2 --request-timeout='1m' \
    -a ${LOCAL_SECRET_JSON} --index-filter-by-os='linux/amd64' \
    --continue-on-error=false --dir="${CATALOG_DIR}"
  if [[ $? -ne 0 ]] ; then
    printf  $(tput setaf 3)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Failed"
    exit -1
  else
    printf  $(tput setaf 2)"%-60s %-30s"$(tput sgr0)"\n" "== Mirroring $CATALOG_SRC" "Completed"
  fi
}

mirrorOperators "redhat-operator-index"
mirrorOperators "certified-operator-index"
