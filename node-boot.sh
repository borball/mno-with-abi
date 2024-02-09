#!/bin/bash

cmd=$1

CURL="curl"
bmc_address=$(echo "$2" |cut -f 2 -d /)
bmc_noproxy=$(echo "$2" |cut -f 1 -d / -s)
if [[ "NOPROXY"=="${bmc_noproxy}" ]]; then
  CURL+=" --noproxy ${bmc_address}"
fi

username_password=$3
iso_image=$4
kvm_uuid=$5

password_var=$(echo "$username_password" |sed -n 's;^.*:ENV{\(.*\)}$;\1;gp')

if [[ -n "${password_var}" ]]; then
  if [[ -z "${!password_var}" ]]; then
    echo "Failed to pick up BMC password from environment variable '${password_var}'"
    exit -1
  fi
  username_password="$(echo $2| cut -f 1 -d :):${!password_var}"
fi

echo "********************************************************"

if [ ! -z $kvm_uuid ]; then
  system=/redfish/v1/Systems/$kvm_uuid
  manager=/redfish/v1/Managers/$kvm_uuid
else
  system=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Systems | jq '.Members[0]."@odata.id"' )
  manager=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Managers | jq '.Members[0]."@odata.id"' )
fi

system=$(sed -e 's/^"//' -e 's/"$//' <<<$system)
manager=$(sed -e 's/^"//' -e 's/"$//' <<<$manager)

system_path=https://$bmc_address$system
manager_path=https://$bmc_address$manager
virtual_media_root=$manager_path/VirtualMedia
virtual_media_path=""

virtual_medias=$($CURL -sku ${username_password} $virtual_media_root | jq '.Members[]."@odata.id"' )
for vm in $virtual_medias; do
  vm=$(sed -e 's/^"//' -e 's/"$//' <<<$vm)
  if [ $($CURL -sku ${username_password} https://$bmc_address$vm | jq '.MediaTypes[]' |grep -ciE 'CD|DVD') -gt 0 ]; then
    virtual_media_path=$vm
  fi
done
virtual_media_path=https://$bmc_address$virtual_media_path

server_secureboot_delete_keys() {
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetKeysType":"DeleteAllKeys"}' \
    -X POST  $system_path/SecureBoot/Actions/SecureBoot.ResetKeys 
}

server_get_bios_config(){
    # Retrieve BIOS config over Redfish
    $CURL -sku ${username_password}  $system_path/Bios |jq
}

server_restart() {
    # Restart
    echo "Restart server."
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_off() {
    # Power off
    echo "Power off server."
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceOff"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_on() {
    # Power on
    echo "Power on server."
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "On"}' -X POST $system_path/Actions/ComputerSystem.Reset
}

virtual_media_eject() {
    # Eject Media
    echo "Eject Virtual Media."
    $CURL --globoff -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{}'  -X POST $virtual_media_path/Actions/VirtualMedia.EjectMedia
}

virtual_media_status(){
    # Media Status
    echo "Virtual Media Status: "
    $CURL -s --globoff -H "Content-Type: application/json" -H "Accept: application/json" \
    -k -X GET --user ${username_password} \
    $virtual_media_path| jq
}

virtual_media_insert(){
    # Insert Media from http server and iso file
    echo "Insert Virtual Media: $iso_image"
    $CURL --globoff -L -w "%{http_code} %{url_effective}\\n" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "{\"Image\": \"${iso_image}\"}" \
    -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia
}

server_set_boot_once_from_cd() {
    # Set boot
    echo "Boot node from Virtual Media Once"
    $CURL --globoff  -L -w "%{http_code} %{url_effective}\\n"  -ku ${username_password}  \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
    -X PATCH $system_path
}

install(){
  echo "-------------------------------"

  echo "Starting OpenShift deployment..."
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

  echo "********************************************************"
}

post_install(){
  virtual_media_eject
}

$cmd



