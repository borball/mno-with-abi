# MNO with OpenShift Agent Based Installer

## Overview

Note: This repo only works for OpenShift 4.12+. 

This is a sister repo of [sno-agent-based-installer](https://github.com/borball/sno-agent-based-installer).

This repo provides a set of script to deploy a multiple nodes(3+0 or 3+x) OpenShift cluster based on Agent Based Installer. 

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
      ipv6:
        ip: 2600:52:7:58::30
      mac: de:ad:be:ff:10:30
      bmc:
        address: 192.168.58.15:8080
        password: Administrator:dummy
        node_uuid: 22222222-1111-1111-0000-000000000000
    - interface: ens1f0
      hostname: master2.compact.outbound.vz.bos2.lab
      ipv4:
        ip: 192.168.58.31
      ipv6:
        ip: 2600:52:7:58::31
      mac: de:ad:be:ff:10:31
      bmc:
        address: 192.168.58.15:8080
        password: Administrator:dummy
        node_uuid: 22222222-1111-1111-0000-000000000001
    - interface: ens1f0
      hostname: master3.compact.outbound.vz.bos2.lab
      ipv4:
        ip: 192.168.58.32
      ipv6:
        ip: 2600:52:7:58::32        
      mac: de:ad:be:ff:10:32
      bmc:
        address: 192.168.58.15:8080
        password: Administrator:dummy
        node_uuid: 22222222-1111-1111-0000-000000000002

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

More supported configuration, please check [config-full.yaml](samples/config-full.yaml). 

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
