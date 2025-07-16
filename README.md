# Multi-Node OpenShift with Agent Based Installer (MNO-with-ABI)

## Overview

This repository provides a comprehensive automation framework for deploying Multi-Node OpenShift (MNO) clusters using the OpenShift Agent Based Installer (ABI). It supports OpenShift 4.12+ and offers extensive customization options for both Day 1 and Day 2 operations.

**Key Features:**
- 🚀 **Automated ISO Generation**: Create bootable OpenShift ISOs with custom configurations
- 🔧 **Day 1 Operations**: Install operators and apply configurations during cluster deployment
- 🛠️ **Day 2 Operations**: Post-installation customization including node labeling, MachineConfigPools, and operator configurations
- 🖥️ **BMC Integration**: Automated node booting via Redfish API
- 🌐 **Dual Stack Support**: IPv4, IPv6, and dual-stack networking
- 📦 **Operator Ecosystem**: Support for 14+ operators with automated configuration
- 🔌 **Disconnected Environments**: Support for air-gapped deployments

## Repository Structure

```
mno-with-abi/
├── README.md                          # This documentation
├── LICENSE                            # Apache License 2.0
├── config.yaml.sample                 # Sample configuration file
├── mno-iso.sh                         # ISO generation script
├── mno-install.sh                     # Automated installation script
├── mno-day2.sh                        # Day 2 operations script
├── node-boot.sh                       # BMC/Redfish node boot script
├── fetch-infra-env.sh                 # Infrastructure environment fetcher
├── inspect-disk.sh                    # Disk inspection utility
├── operators/                         # Operator definitions and configurations
│   ├── operators.yaml                 # Supported operators registry
│   ├── ptp/                          # PTP Operator configs
│   ├── sriov/                        # SR-IOV Network Operator configs
│   ├── local-storage/                # Local Storage Operator configs
│   ├── rhacm/                        # Red Hat ACM configs
│   ├── metallb/                      # MetalLB Operator configs
│   └── [+9 more operators]
├── templates/                         # Jinja2 templates
│   ├── agent-config.yaml.j2          # Agent configuration template
│   ├── install-config.yaml.j2        # Install configuration template
│   └── day1/                         # Day 1 operation templates
├── samples/                           # Sample configurations
│   └── config-full.yaml              # Complete configuration example
├── extra-manifests/                   # Custom manifests
│   ├── day1/                         # Day 1 custom resources
│   └── day2/                         # Day 2 custom resources
├── scale/                            # Scaling configurations
├── test/                             # Test configurations and scripts
│   ├── compact/                      # Compact cluster tests
│   ├── hub/                          # Hub cluster tests
│   ├── odf/                          # ODF-specific tests
│   └── vhub/                         # Virtual hub tests
└── mirror/                           # Mirroring and disconnected configs
```

## Prerequisites

### System Requirements
- **OS**: Linux-based system (RHEL, CentOS, Fedora)
- **OpenShift**: 4.12+ 
- **Network**: Access to OpenShift mirror sites (or local mirrors for disconnected)

### Dependencies
```bash
# Required tools
yq                    # YAML processor
jinja2-cli           # Template engine
oc                   # OpenShift CLI
curl                 # HTTP client
jq                   # JSON processor

# Auto-installed by scripts if missing
pip3 install --user jinja2-cli
pip3 install --user jinja2-cli[yaml]
```

### Access Requirements
- **Pull Secret**: Valid OpenShift pull secret
- **SSH Key**: SSH public key for cluster access
- **BMC Access**: Redfish/IPMI access to target nodes (for automated deployment)
- **HTTP Server**: Web server for hosting ISO images

## Quick Start

### 1. Configuration Setup

Create a configuration file based on the sample:

```bash
cp config.yaml.sample my-cluster.yaml
# Edit my-cluster.yaml with your specific settings
```

**Basic Configuration Structure:**
```yaml
cluster:
  domain: example.com
  name: my-cluster
  apiVIPs: ["192.168.1.100"]
  ingressVIPs: ["192.168.1.101"]

hosts:
  common:
    ipv4:
      enabled: true
      dhcp: false
      machine_network_cidr: 192.168.1.0/24
      dns: 192.168.1.1
      gateway: 192.168.1.1
    disk: /dev/sda
  
  masters:
    - interface: ens1f0
      hostname: master1.my-cluster.example.com
      ipv4:
        ip: 192.168.1.10
      mac: aa:bb:cc:dd:ee:01
      bmc:
        address: 192.168.1.110:443
        password: admin:password123

pull_secret: /path/to/pull-secret.json
ssh_key: /path/to/ssh-key.pub
iso:
  address: http://webserver.example.com/iso/my-cluster.iso
```

### 2. Generate ISO

```bash
./mno-iso.sh my-cluster.yaml
```

**With specific OpenShift version:**
```bash
./mno-iso.sh my-cluster.yaml 4.14.8
```

### 3. Deploy Cluster

**Manual deployment:**
```bash
# Copy the generated ISO to your web server
cp instances/my-cluster/agent.x86_64.iso /var/www/html/iso/my-cluster.iso

# Boot nodes manually from BMC console
```

**Automated deployment:**
```bash
./mno-install.sh my-cluster
```

### 4. Day 2 Operations (Optional)

```bash
./mno-day2.sh my-cluster.yaml
```

## Detailed Configuration

### Cluster Configuration

#### Basic Cluster Settings
```yaml
cluster:
  domain: outbound.vz.bos2.lab        # Base domain
  name: production                     # Cluster name
  apiVIPs: ["192.168.1.100"]          # API VIP addresses
  ingressVIPs: ["192.168.1.101"]      # Ingress VIP addresses
```

#### Network Configuration

**IPv4 Configuration:**
```yaml
hosts:
  common:
    ipv4:
      enabled: true
      dhcp: false                      # Static IP configuration
      machine_network_cidr: 192.168.1.0/24
      machine_network_prefix: 24
      dns: 192.168.1.1
      gateway: 192.168.1.1
      # Optional: Custom network CIDRs
      cluster_network_cidr: 10.128.0.0/14
      cluster_network_host_prefix: 23
      service_network: 172.30.0.0/16
```

**IPv6 Configuration:**
```yaml
hosts:
  common:
    ipv6:
      enabled: true
      dhcp: false
      machine_network_cidr: 2001:db8::/64
      machine_network_prefix: 64
      dns: 2001:db8::1
      gateway: 2001:db8::1
```

**VLAN Configuration:**
```yaml
hosts:
  common:
    vlan:
      enabled: true
      name: ens1f0.100
      id: 100
```

#### Node Configuration

**Master Nodes:**
```yaml
hosts:
  masters:
    - interface: ens1f0
      hostname: master1.cluster.example.com
      ipv4:
        ip: 192.168.1.10
      ipv6:
        ip: 2001:db8::10
      mac: aa:bb:cc:dd:ee:01
      bmc:
        address: 192.168.1.110:443
        password: admin:password123
        node_uuid: 12345678-1234-5678-9abc-123456789abc  # Optional
```

**Worker Nodes:**
```yaml
hosts:
  workers:
    - interface: ens1f0
      hostname: worker1.cluster.example.com
      ipv4:
        ip: 192.168.1.20
      mac: aa:bb:cc:dd:ee:02
      bmc:
        address: 192.168.1.120:443
        password: admin:password123
      roles:
        - worker
        - infra
        - storage
      labels:
        - "node.openshift.io/os_id=rhcos"
        - "custom.label/type=compute"
```

### Day 1 Operations

#### Supported Operators

The repository supports 14+ operators for Day 1 installation:

| Operator | Description | Configuration |
|----------|-------------|---------------|
| **rhacm** | Red Hat Advanced Cluster Management | Cluster lifecycle management |
| **gitops** | Red Hat OpenShift GitOps | GitOps workflows |
| **talm** | Topology Aware Lifecycle Manager | Edge cluster management |
| **local-storage** | Local Storage Operator | Local disk management |
| **odf** | OpenShift Data Foundation | Persistent storage |
| **ptp** | PTP Operator | Precision Time Protocol |
| **sriov** | SR-IOV Network Operator | High-performance networking |
| **metallb** | MetalLB Operator | Load balancing |
| **nmstate** | NMState Operator | Network state management |
| **lvm** | LVM Storage Operator | Logical volume management |
| **mce** | Multicluster Engine | Multi-cluster orchestration |
| **cluster-logging** | OpenShift Logging | Centralized logging |
| **kubevirt-hyperconverged** | OpenShift Virtualization | Virtual machine management |

#### Operator Configuration Example

```yaml
day1:
  operators:
    rhacm:
      enabled: true
    local-storage:
      enabled: true
    odf:
      enabled: true
    ptp:
      enabled: true
    sriov:
      enabled: true
    metallb:
      enabled: true
      config:
        address_pools:
          - name: default
            protocol: layer2
            addresses: ["192.168.1.200-192.168.1.220"]
```

#### Container Runtime Configuration

```yaml
day1:
  crun: true  # Enable crun container runtime (4.13+)
```

#### Custom Manifests

Place custom Kubernetes manifests in `extra-manifests/day1/`:
- `*.yaml` files are copied directly
- `*.yaml.j2` files are rendered as Jinja2 templates

### Day 2 Operations

#### Node Labeling and Roles

```yaml
day2:
  node_labels_enabled: true

hosts:
  workers:
    - hostname: worker1.cluster.example.com
      roles:
        - worker
        - infra
        - storage
      labels:
        - "node.openshift.io/os_id=rhcos"
        - "cluster.ocs.openshift.io/openshift-storage="
        - "node-role.kubernetes.io/infra="
```

#### MachineConfigPools and Performance Profiles

```yaml
day2:
  mcp:
    - name: "worker-cnf"
      role: "worker-cnf"
      performance_profile:
        enabled: true
        name: performance-worker-cnf
        manifest: performance-profile.yaml.j2
        cpu:
          isolated: "4-23,28-47"
          reserved: "0-3,24-27"
        hugepages:
          default: 1G
          pages:
            - size: 1G
              count: 32
        numa:
          policy: "restricted"
        realtime:
          enabled: true
```

#### Tuned Profiles

```yaml
day2:
  tuned_profiles:
    - tuned-worker-cnf.yaml
    - tuned-storage.yaml
```

#### Operator-Specific Day 2 Configuration

```yaml
day2:
  operators:
    metallb:
      selector:
        role: "worker"
      address_pools:
        - name: default
          protocol: layer2
          addresses: ["192.168.1.200-192.168.1.220"]
    
    local-storage:
      storage_classes:
        - name: local-ssd
          device_paths: ["/dev/sdb"]
    
    odf:
      dual_stack: false
      ip_family: IPv4
      storage_device_count: 3
      storage_class: local-ssd
```

### Disconnected Environment Support

#### Container Registry Configuration

```yaml
container_registry:
  url: registry.example.com:5000
  username: admin
  password: password123
  
  # Image source mapping
  image_source: /path/to/image-source-policy.yaml
  
  # Catalog sources
  catalog_sources:
    defaults:
      - redhat-operators
      - certified-operators
    customs:
      - name: custom-catalog
        image: registry.example.com:5000/custom/catalog:latest
        displayName: Custom Catalog
        publisher: Custom Publisher
  
  # Image Content Source Policy
  icsp:
    - /path/to/icsp-config.yaml
```

#### Mirror Registry Setup

```yaml
mirror:
  registry: registry.example.com:5000
  operators:
    - local-storage-operator
    - odf-operator
    - ptp-operator
  additional_images:
    - registry.redhat.io/ubi8/ubi:latest
```

### Advanced Features

#### Proxy Configuration

```yaml
proxy:
  enabled: true
  http: http://proxy.example.com:8080
  https: https://proxy.example.com:8080
  noproxy: "localhost,127.0.0.1,.example.com"
```

#### Additional Trust Bundle

```yaml
additional_trust_bundle: /path/to/ca-bundle.pem
```

#### BMC Configuration

```yaml
hosts:
  common:
    bmc:
      bypass_proxy: true  # Bypass proxy for BMC operations
  
  masters:
    - bmc:
        address: 192.168.1.110:443
        password: admin:password123
        node_uuid: 12345678-1234-5678-9abc-123456789abc
        vendor: dell  # dell, hp, lenovo, supermicro
```

## Scripts Reference

### mno-iso.sh

**Purpose**: Generate OpenShift installation ISO with custom configurations

**Usage**:
```bash
./mno-iso.sh [config-file] [ocp-version]
```

**Examples**:
```bash
./mno-iso.sh                           # Uses config.yaml with stable-4.12
./mno-iso.sh my-cluster.yaml          # Uses my-cluster.yaml with stable-4.12
./mno-iso.sh my-cluster.yaml 4.14.8   # Uses my-cluster.yaml with 4.14.8
./mno-iso.sh my-cluster.yaml nightly-4.15  # Uses nightly build
```

**Features**:
- Downloads OpenShift installer automatically
- Supports multiple OpenShift versions
- Renders Jinja2 templates
- Installs Day 1 operators
- Configures container runtime
- Sets up catalog sources

### mno-install.sh

**Purpose**: Automated cluster installation with BMC integration

**Usage**:
```bash
./mno-install.sh [cluster-name]
```

**Features**:
- Deploys ISO to HTTP server
- Boots nodes via Redfish API
- Monitors installation progress
- Tracks cluster stability
- Approves InstallPlans automatically
- Provides detailed progress reporting

**Installation Flow**:
1. 🔧 Deploy ISO to web server
2. 🖥️ Boot all nodes via BMC
3. ⏳ Wait for Assisted Service API
4. 📊 Monitor installation progress
5. 🔄 Wait for node reboot
6. ✅ Verify cluster stability
7. 📦 Approve operator InstallPlans

### mno-day2.sh

**Purpose**: Post-installation cluster customization

**Usage**:
```bash
./mno-day2.sh config.yaml
```

**Features**:
- Node labeling and role assignment
- MachineConfigPool creation
- Performance profile configuration
- Tuned profile application
- Operator-specific configurations
- Custom resource application


## Testing

The repository includes comprehensive test configurations:

### Test Scenarios

- **Compact Cluster**: 3-node compact cluster configuration
- **Hub Cluster**: Multi-cluster hub setup
- **ODF Testing**: Storage-specific configurations
- **Virtual Hub**: Virtualized hub cluster setup

### Running Tests

```bash
# Navigate to test directory
cd test/compact

# Run compact cluster test
../../mno-iso.sh compact-cluster.yaml

# Install and validate
../../mno-install.sh compact-cluster
```

## Contributing

### Development Setup

```bash
# Clone repository
git clone https://github.com/borball/mno-with-abi.git
cd mno-with-abi

# Create test configuration
cp config.yaml.sample test-config.yaml

# Run tests
./mno-iso.sh test-config.yaml
```

### Adding New Operators

1. Create operator directory in `operators/`
2. Add operator definition to `operators/operators.yaml`
3. Create Day 1 and Day 2 configurations
4. Add documentation and examples
5. Test thoroughly

### Submitting Changes

1. Fork the repository
2. Create feature branch
3. Implement changes with tests
4. Update documentation
5. Submit pull request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Support and Community

- **Issues**: Report bugs and request features via GitHub Issues
- **Discussions**: Join community discussions
- **Documentation**: Contribute to documentation improvements
- **Testing**: Help test new features and configurations

---

**Note**: This repository is continuously evolving. Check the latest releases for new features and improvements.

