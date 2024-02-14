# MNO with OpenShift Agent Based Installer

## Overview

Note: This repo only works for OpenShift 4.12+. 

This is a sister repo of [sno-agent-based-installer](https://github.com/borball/sno-agent-based-installer).

This repo provides a set of script to deploy a multiple nodes(3+0 or 3+x) OpenShift cluster based on [OpenShift Agent Based Installer](https://docs.openshift.com/container-platform/4.12/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html);
It also provides flexibility to install commonly-used operators and apply the configurations in day1 and/or day2. 

## Configuration

Follow the config.yaml.sample to prepare a configuration file. 

```yaml
cluster:
  domain: outbound.vz.bos2.lab
  name: compact
  apiVIPs:
    - 192.168.58.90
    - 2600:52:7:58::90
  ingressVIPs:
    - 192.168.58.91
    - 2600:52:7:58::91

hosts:
  common:
    ipv4:
      enabled: true
      dhcp: false
      machine_network_cidr: 192.168.58.0/25
      machine_network_prefix: 25
      #cluster_network_cidr:
      #cluster_network_host_prefix:
      #service_network:
      dns: 192.168.58.15
      gateway: 192.168.58.1
    ipv6:
      enabled: true
      dhcp: false
      machine_network_cidr: 2600:52:7:58::/64
      machine_network_prefix: 64
      #cluster_network_cidr:
      #cluster_network_host_prefix:
      #service_network:
      dns: 2600:52:7:58::15
      gateway: 2600:52:7:58::1
    vlan:
      enabled: false
      name: ens1f0.58
      id: 58
    disk: /dev/vda

  masters:
    - interface: ens1f0
      hostname: master1.compact.outbound.vz.bos2.lab
      ipv4:
        ip: 192.168.58.30
      mac: de:ad:be:ff:10:30
      bmc:
        address: 192.168.58.30:8080
        password: Administrator:dummy
    - interface: ens1f0
      hostname: master2.compact.outbound.vz.bos2.lab
      ipv4:
        ip: 192.168.58.31
      mac: de:ad:be:ff:10:31
      bmc:
        address: 192.168.58.31:8080
        password: Administrator:dummy
    - interface: ens1f0
      hostname: master3.compact.outbound.vz.bos2.lab
      ipv4:
        ip: 192.168.58.32
      mac: de:ad:be:ff:10:32
      bmc:
        address: 192.168.58.32:8080
        password: Administrator:dummy

proxy:
  enabled: false
  http:
  https:
  noproxy:

pull_secret: /root/pull-secret.json
ssh_key: /root/.ssh/id_rsa.pub

iso:
  address: http://192.168.58.15/iso/compact.iso
```

## Day1

Some operators can be installed as day1 operations, following is an example to do it:

```yaml
day1:
  operators:
    local-storage:
      enabled: true
    odf:
      enabled: true
```

All supported operators: [operators.yaml](operators/operators.yaml)

You can also put the additional manifests(CR) in folder extra-manifests/day1/, so that those CRs can be included as day1 operations. You can find an example [here](test/odf/extra-manifests/day1/98-disk-partition-mc.yaml).

## Generate ISO

```shell
./mno-iso.sh config.yaml
```

or

```shell
./mno-iso.sh config.yaml 4.12.30
```

Copy the ISO into your HTTP server. 

## OCP installation

```shell
./mno-install.sh config.yaml
```

## Day2 operations

The repo provides a script to do the commonly-required day2 operations such as 'node labeling', 'custom MachineConfigPool', 'Performance Profile', 'Tuned Profile' and operator specific day2 configurations.

To achieve this, prepare the config.yaml based on an example in [config-full.yaml](samples/config-full.yaml). 

### Node roles and labeling

```yaml
  workers:
    - hostname: worker1.cluster6.outbound.vz.bos2.lab
      roles:
        - infra
      labels:
        - cluster.ocs.openshift.io/openshift-storage=

day2:
  node_labels_enabled: true
```

### MachineConfigPool and PerformanceProfile

```yaml
day2:
  mcp:
    - name: "worker-hp"
      role: "worker-hp"
      performance_profile:
        enabled: true
        name: performance-profile-worker-hp
        #manifest can be yaml or j2 template file, find from extra-manifests/day2/performance-profiles/ if a relative path provided
        manifest: performance-profile.yaml.j2
        #following are free format, used to build the performance-profile based on the j2 template
        cpu:
          isolated: "2-13,16-27,30-41,44-55"
          reserved: "0,28,1,29,14,42,15,43"
        hugepages:
          default: 2M
          pages:
            - size: 2M
              count: 32768
              #node: 1
        numa:
          policy: "single-numa-node"
    - name: worker
      role: worker
      performance-profile:
        enabled: true
        name: performance-profile-worker
        #manifest can be yaml or j2 template file, find from extra-manifests/day2/performance-profiles/ if a relative path provided
        manifest: performance-profile-worker.yaml
```

### Tuned Profile

```yaml
day2:
  tuned_profiles:
    - tuned-worker.yaml
```

### Operator specific config

```yaml
day2:
  operators:
    #op:
    #Supported 'op' can be found from operators/operators.yaml. For example: local-storage or nmstate
    #Put additional crs desired to be applied towards the operator in folder extra-manifests/day2/$op/, can support yaml or j2 file;
    #The yaml files together with the rendered files based on j2 templates will be executed with a respected order by file name.
    #Put bash scripts desired to be executed in folder extra-manifests/day2/$op/, can support *.sh
    #Other free-format data to define variables, used to build the extra-manifests based on the template provided in extra-manifests/day2/$op/
    #following is an example for metallb operator, #to add more examples.
    metallb:
      selector:
        role: "worker"
    local-storage: {}
    odf:
      # for dual stack, set to true
      # other wise, set to false and specify the ip_family IPv6 or IPv4
      dual_stack: false
      ip_family: IPv4
      # number of storage device in the storage device set
      # should be number of node marked for providing disk for ODF
      storage_device_count: 3
```

### mno-day2

More supported configuration, please check [config-full.yaml](samples/config-full.yaml).

Run script mno-day2.sh to apply all day2 operations based on config.yaml.

```shell
./mno-day2.sh config.yaml
```

