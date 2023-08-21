# used for my own test

ssh 192.168.58.14 kcli stop vm compact-master0 compact-master1 compact-master2 compact-master3 compact-worker0
ssh 192.168.58.14 kcli delete vm compact-master0 compact-master1 compact-master2 compact-master3 compact-worker0 -y
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-000000000000 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,50] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:30\"}"] compact-master0'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-000000000001 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,50] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:31\"}"] compact-master1'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-000000000002 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,50] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:32\"}"] compact-master2'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-000000000003 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,50] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:33\"}"] compact-master3'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-000000000004 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,50] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:34\"}"] compact-worker0'

ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf compact
./mno-iso.sh config-compact.yaml
cp compact/agent.x86_64.iso /var/www/html/iso/compact.iso

./mno-install.sh config-compact.yaml


oc get node --kubeconfig compact/auth/kubeconfig
oc get clusterversion --kubeconfig compact/auth/kubeconfig

echo "Installation in progress, please check it in 30m."
