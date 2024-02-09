#!/bin/bash

LOCAL_REGISTRY="registry.service.local:5000"
LOCAL_REPOSITORY="library/openshift-release-dev"
PRODUCT_REPO="openshift-release-dev"
LOCAL_SECRET_JSON="./pull-secret.json"
RELEASE_NAME="ocp-release"
ARCHITECTURE="x86_64"

OCP_RELEASE=$1
if [[ -z "${OCP_RELEASE}" ]]; then
  echo "Usage: $0 <OCP Z release>"
  echo ""
  echo "Example: $0 4.12.33"
  echo ""
  exit 0
fi

echo "Running dry run"
oc adm release mirror --max-per-registry=1 --request-timeout='1m' \
  -a ${LOCAL_SECRET_JSON} \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} \
  --dry-run > /dev/null
if [[ $? -ne 0 ]]; then
  exit
fi

echo "Mirroring registry"
echo " from quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE}"
echo " to ${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}"
oc adm release mirror --max-per-registry=2 --request-timeout='1m' -a ${LOCAL_SECRET_JSON} \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} \
  --release-image-signature-to-dir=./${OCP_RELEASE}
