#!/bin/bash

bmc_address=$1
username_password=$2
iso_image=$3
kvm_uuid=$4

if [ ! -z $kvm_uuid ]; then
  system=/redfish/v1/Systems/$kvm_uuid
  manager=/redfish/v1/Managers/$kvm_uuid
else
  system=$(curl -sku ${username_password}  https://$bmc_address/redfish/v1/Systems | jq '.Members[0]."@odata.id"' )
  manager=$(curl -sku ${username_password}  https://$bmc_address/redfish/v1/Managers | jq '.Members[0]."@odata.id"' )
fi

system=$(sed -e 's/^"//' -e 's/"$//' <<<$system)
manager=$(sed -e 's/^"//' -e 's/"$//' <<<$manager)

system_path=https://$bmc_address$system
manager_path=https://$bmc_address$manager
virtual_media_root=$manager_path/VirtualMedia
virtual_media_path=""

virtual_medias=$(curl -sku ${username_password} $virtual_media_root | jq '.Members[]."@odata.id"' )
for vm in $virtual_medias; do
  vm=$(sed -e 's/^"//' -e 's/"$//' <<<$vm)
  if [ $(curl -sku ${username_password} https://$bmc_address$vm | jq '.MediaTypes[]' |grep -ciE 'CD|DVD') -gt 0 ]; then
    virtual_media_path=$vm
  fi
done
virtual_media_path=https://$bmc_address$virtual_media_path

server_secureboot_delete_keys() {
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetKeysType":"DeleteAllKeys"}' \
    -X POST  $system_path/SecureBoot/Actions/SecureBoot.ResetKeys 
}

server_get_bios_config(){
    # Retrieve BIOS config over Redfish
    curl -sku ${username_password}  $system_path/Bios |jq
}

server_restart() {
    # Restart
    echo "Restart server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_off() {
    # Power off
    echo "Power off server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceOff"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_on() {
    # Power on
    echo "Power on server."
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "On"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

virtual_media_eject() {
    # Eject Media
    echo "Eject Virtual Media."
    curl --globoff -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{}'  -X POST $virtual_media_path/Actions/VirtualMedia.EjectMedia
}

virtual_media_status(){
    # Media Status
    echo "Virtual Media Status: "
    curl -s --globoff -H "Content-Type: application/json" -H "Accept: application/json" \
    -k -X GET --user ${username_password} \
    $virtual_media_path| jq
}

virtual_media_insert(){
    # Insert Media from http server and iso file
    echo "Insert Virtual Media: $iso_image"
    curl --globoff -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "{\"Image\": \"${iso_image}\"}" \
    -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia
}

server_set_boot_once_from_cd() {
    # Set boot
    echo "Boot node from Virtual Media Once"
    curl --globoff  -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password}  \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
    -X PATCH $system_path
}

echo "-------------------------------"

echo "Starting SNO deployment..."
echo
server_power_off

sleep 15

echo "-------------------------------"
echo
virtual_media_eject
echo "-------------------------------"
echo
virtual_media_insert
echo "-------------------------------"
echo
virtual_media_status
echo "-------------------------------"
echo
server_set_boot_once_from_cd
echo "-------------------------------"

sleep 10
echo
server_power_on
#server_restart
echo
echo "-------------------------------"
echo "Node is booting from virtual media mounted with $iso_image, check your BMC console to monitor the installation progress."
echo 
echo
echo -n "Node booting."
