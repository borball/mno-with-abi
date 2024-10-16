# HOW-TO mirror OpenShift Container Images

Based on [Mirroring images for a disconnected installation using the oc-mirror plugin](https://docs.openshift.com/container-platform/4.16/installing/disconnected_install/installing-mirroring-disconnected.html]).

## Download CLIs

Download all required tools from [OpenShift Mirror Site](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/):
| Tool | Description |
| - | - |
| oc   | OpenShift Client |
| opm | CLI to interact with operator-registry and build indexes of operator content. |
| oc-mirror | Create and publish user-configured mirrors with a declarative configuration input. |

| :warning: WARNING  |
|:-------------------------|
| For RHEL ealier than 9.4, adjust URL below to download version for RHEL8 |

Example: downloading for 4.16.2 and extract to ~/bin,

```bash
$ OC_VERSION=4.16.2
$ DEST=~/bin

$ curl -s -o - https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/openshift-client-linux-${OC_VERSION}.tar.gz | tar zxvf - -C $DEST oc kubectl
oc
kubectl

$ curl -s -o - https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/opm-linux-${OC_VERSION}.tar.gz | tar zxvf - -C $DEST opm
opm

$ curl -s -o - https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/oc-mirror.tar.gz | tar zxvf - -C $DEST oc-mirror
oc-mirror

# enable bash auto completions
$ source <($DEST/oc completion bash)
$ source <($DEST/opm completion bash)
```

## Configuring credentials

1. Download your registry.redhat.io pull secret from [Red Hat OpenShift Cluster Manager](https://console.redhat.com/openshift/install/pull-secret).
2. Add the credential for the private registry to the same file.
3. Rename the file as config.json and placed in auth folder.
4. Set up environment variable `DOCKER_CONFIG` to the directory contains the config.json file.

Example:

```bash
$ export DOCKER_CONFIG=${HOME}/mirror/openshift/auth
$ tree ${HOME}/mirror/openshift
/home/user/mirror/openshift
└── auth
    └── config.json

1 directory, 1 file
```

## Creating the image set configuration

1. Create an initial image set configuration to local disk

   ```bash
   oc mirror init file://images > imageset-config.4.16.yaml
   ```

2. Update the imageset configuration to include desired platform versions and operators.
   Use `opm` to search for operator default channel.

   ```bash
   opm render registry.redhat.io/redhat/redhat-operator-index:v4.16| jq -r -c 'select(.schema=="olm.package")|[.name,.defaultChannel]'
   ```

Example: configuration file for OpenShift `fast-4.16` channel, version 4.16.0 to 4.16.2
```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
storageConfig:
  local:
    path: ./images
mirror:
  platform:
    architectures:
    - amd64
    channels:
    - name: fast-4.16
      type: ocp
      minVersion: 4.16.0
      maxVersion: 4.16.2
      shortestPath: true
    graph: true
  operators:
  - catalog: registry.redhat.io/redhat/certified-operator-index:v4.16
    packages:
    - name: sriov-fec
      channels:
      - name: stable
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.16
    packages:
    - name: local-storage-operator
      channels:
      - name: stable
    - name: sriov-network-operator
      channels:
      - name: stable
    - name: ptp-operator
      channels:
      - name: stable
    - name: odf-operator
      channels:
      - name: stable-4.15
    - name: kubernetes-nmstate-operator
      channels:
      - name: stable
    - name: metallb-operator
      channels:
      - name: stable
    - name: cluster-logging
      channels:
      - name: stable-5.9
    - name: lifecycle-agent
      channels:
      - name: stable
    - name: redhat-oadp-operator
      channels:
      - name: stable-1.4
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  helm: {}
```

## Mirror images to disk

Use file destination to mirror it to the local disk first instead of the local registry.  This allows us to push the images to multiple registries.  The result can also be transfer and used for populating the registroy in network without internet connection.

```bash
$ oc mirror --config=imageset-config.4.16.yaml --max-per-registry 2 file://images
Creating directory: images/oc-mirror-workspace/src/publish
Creating directory: images/oc-mirror-workspace/src/v2
Creating directory: images/oc-mirror-workspace/src/charts
Creating directory: images/oc-mirror-workspace/src/release-signatures
No metadata detected, creating new workspace
...
info: Mirroring completed in 15m44.48s (46.89MB/s)
Creating archive images/mirror_seq1_000000.tar
```

## Mirror from disk to registory

Run the oc mirror command to process the image set file on disk and mirror the contents to a target mirror registry

```bash
$ oc mirror --from=./mirror_seq1_000000.tar docker://registry.example.com:5000/repo/redhat-mirror
Checking push permissions for registry.example.com:5000
Publishing image set from archive "./mirror_seq1_000000.tar" to registry "registry.example.com:5000"
...
Writing image mapping to oc-mirror-workspace/results-1720573445/mapping.txt
Writing UpdateService manifests to oc-mirror-workspace/results-1720573445
Writing CatalogSource manifests to oc-mirror-workspace/results-1720573445
Writing ICSP manifests to oc-mirror-workspace/results-1720573445
```

Verify that YAML files are present for the ImageContentSourcePolicy and CatalogSource resources in the results directory.

```bash
$ tree oc-mirror-workspace/results-1720573445
oc-mirror-workspace/results-1720573445
├── catalogSource-cs-certified-operator-index.yaml
├── catalogSource-cs-redhat-operator-index.yaml
├── charts
├── imageContentSourcePolicy.yaml
├── mapping.txt
├── release-signatures
│   ├── signature-sha256-a0ef946ef8ae75ae.json
│   └── signature-sha256-c5bcd0298deee99c.json
└── updateService.yaml
```