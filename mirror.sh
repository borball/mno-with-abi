#!/bin/bash

OCP_RELEASE=${1}
LOCAL_REGISTRY="provisioner.srvc.lan:8443"
LOCAL_REPOSITORY="operators/redhat"
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

OPERATOR_RELEASE=$(echo "${OCP_RELEASE}" |cut -f 1-2 -d .)
OPERATOR_LIST=("odf-operator" "local-storage-operator" "sriov-network-operator" "kubernetes-nmstate-operator")

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
CATALOG_DIR="${BUILD_DIR}/redhat-operator-index"

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

# see https://docs.openshift.com/container-platform/4.12/cli_reference/opm/cli-opm-install.html
# https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest-${OPERATOR_RELEASE}/opm-linux.tar.gz
mkdir -p ${CATALOG_DIR}
if [[ ! -f "${CATALOG_DIR}.Dockerfile" ]]; then
  echo "Generator ${CATALOG_DIR}.Dockerfile"
  # DO NOT USE ORIGINAL OPREATOR INDEX unless we are only adding new operators
  opm generate dockerfile ${CATALOG_DIR}
  [[ $? -ne 0 ]] && exit -1
fi

if [[ ! -f "${CATALOG_DIR}.json" ]]; then
  echo "Extract the index.json from registry.redhat.io/${PRODUCT_REPO}/redhat-operator-index:v${OPERATOR_RELEASE}"
  opm render registry.redhat.io/${PRODUCT_REPO}/redhat-operator-index:v${OPERATOR_RELEASE} > ${CATALOG_DIR}.json
  [[ $? -ne 0 ]] && exit -1
fi

echo "Filter ${CATALOG_DIR}.json"
jq -M "$(filter_expression)" "${CATALOG_DIR}.json" > ${CATALOG_DIR}/index.json
[[ $? -ne 0 ]] && exit -1

echo "Validate ${CATALOG_DIR}"
opm validate ${CATALOG_DIR}
[[ $? -ne 0 ]] && exit -1

echo "Build container image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/redhat-operator-index:v${OPERATOR_RELEASE}"
${cmd} build ${BUILD_DIR} -f ${CATALOG_DIR}.Dockerfile \
    -t ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/redhat-operator-index:v${OPERATOR_RELEASE}
[[ $? -ne 0 ]] && exit -1

echo "Push container image ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/redhat-operator-index:v${OPERATOR_RELEASE}"
${cmd} push ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/redhat-operator-index:v${OPERATOR_RELEASE}
[[ $? -ne 0 ]] && exit -1

# mirror based on the pruned index
echo "Mirroring operator images"
oc adm catalog mirror ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}/redhat-operator-index:v${OPERATOR_RELEASE} \
  ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  -a ${LOCAL_SECRET_JSON} --index-filter-by-os='linux/amd64'