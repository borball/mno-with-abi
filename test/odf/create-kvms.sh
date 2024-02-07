# used for my own test

ssh 192.168.58.14 kcli stop vm odf-master1 odf-master2 odf-master3 odf-worker1 odf-worker2 odf-worker3
ssh 192.168.58.14 kcli delete vm odf-master1 odf-master2 odf-master3 odf-worker1 odf-worker2 odf-worker3 -y
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000061 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:61\"}"] odf-master1'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000062 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:62\"}"] odf-master2'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000063 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:63\"}"] odf-master3'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000064 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,100] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:64\"}"] odf-worker1'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000065 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,100] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:65\"}"] odf-worker2'
ssh 192.168.58.14 'kcli create vm -P uuid=22222222-1111-1111-0000-111100000066 -P start=False -P memory=20480 -P numcpus=16 -P disks=[122,100] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:66\"}"] odf-worker3'

ssh 192.168.58.14 kcli list vm
systemctl restart sushy-tools.service
