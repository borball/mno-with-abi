#!/bin/bash

cmd="install"
bmc_noproxy=0
CURL="curl -s"

while getopts "c:h:u:i:k:l:n" flag; do
  case ${flag} in
   c)
     cmd="${OPTARG}"
     ;;
   h) 
     bmc_address="${OPTARG}"
     ;;
   u)
     username_password="${OPTARG}"
     ;;
   i)
     iso_image="${OPTARG}"
     ;;
   k)
     kvm_uuid="${OPTARG}"
     ;;
   l)
     log_file="${OPTARG}"
     ;;
   n)
     bmc_noproxy=1
     ;;
  esac
done

password_var=$(echo "$username_password" |sed -n 's;^.*:ENV{\(.*\)}$;\1;gp')

if [[ bmc_noproxy == 1 ]]; then
  CURL+=" --noproxy ${bmc_address}"
fi

if [[ -n "${password_var}" ]]; then
  if [[ -z "${!password_var}" ]]; then
    echo "FATAL: failed to pick up BMC password from environment variable '${password_var}'"
    exit -1
  fi
  username_password="$(echo $username_password| cut -f 1 -d :):${!password_var}"
fi

rest_response=$(mktemp)

if [ ! -z $kvm_uuid ]; then
  system=/redfish/v1/Systems/$kvm_uuid
  manager=/redfish/v1/Managers/$kvm_uuid
else
  system=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Systems | jq '.Members[0]."@odata.id"' )
  manager=$($CURL -sku ${username_password}  https://$bmc_address/redfish/v1/Managers | jq '.Members[0]."@odata.id"' )
fi

system=$(sed -e 's/^"//' -e 's/"$//' <<<$system)
manager=$(sed -e 's/^"//' -e 's/"$//' <<<$manager)

if [ "$manager" == "null" ] || [ "$system" == "null" ]; then
  echo "FATAL: either redfish system or manager is 'null', please check!"
  exit -1
fi

system_path=https://$bmc_address$system
manager_path=https://$bmc_address$manager
virtual_media_root=$manager_path/VirtualMedia
virtual_media_path=""

virtual_medias=$($CURL -sku ${username_password} $virtual_media_root | jq '.Members[]."@odata.id"')
for vm in $virtual_medias; do
  vm=$(sed -e 's/^"//' -e 's/"$//' <<<$vm)
  if [ $($CURL -sku ${username_password} https://$bmc_address$vm | jq '.MediaTypes[]' |grep -ciE 'CD|DVD') -gt 0 ]; then
    virtual_media_path=$vm
  fi
done
virtual_media_path=https://$bmc_address$virtual_media_path

show_info(){
  printf  $(tput setaf 2)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

show_warn(){
  printf  $(tput setaf 3)"%-54s %-10s"$(tput sgr0)"\n" "$@"
}

server_secureboot_delete_keys() {
    $CURL --globoff  -L -w "%{http_code}" -ku ${username_password} \
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
    $CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    -X POST $system_path/Actions/ComputerSystem.Reset
}

server_power_off() {
    # Power off
    local action="Power off Server"
    rest_result=$($CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -o "$rest_response" -d '{"ResetType": "ForceOff"}' -X POST $system_path/Actions/ComputerSystem.Reset)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

server_power_on() {
    # Power on
    local action="Power on Server"
    rest_result=$($CURL --globoff  -L -w "%{http_code}" -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" -d '{"ResetType": "On"}' \
      -o "$rest_response" -X POST $system_path/Actions/ComputerSystem.Reset)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_eject() {
    # Eject Media
    local action="Eject Virtual Media"
    rest_result=$($CURL --globoff -L -w "%{http_code}"  -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" -d '{}' \
      -o "$rest_response" -X POST $virtual_media_path/Actions/VirtualMedia.EjectMedia)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

virtual_media_status(){
    # Media Status
    echo "Virtual Media Status: "
    $CURL --globoff -H "Content-Type: application/json" -H "Accept: application/json" \
      -k -X GET --user ${username_password} \
      $virtual_media_path| jq
}

virtual_media_insert(){
    # Insert Media from http server and iso file
    local action="Insert Virtual Media"
    rest_result=$($CURL --globoff -L -w "%{http_code}" -ku ${username_password} \
      -H "Content-Type: application/json" -H "Accept: application/json" -d "{\"Image\": \"${iso_image}\"}" \
      -o "$rest_response" -X POST $virtual_media_path/Actions/VirtualMedia.InsertMedia)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

server_set_boot_once_from_cd() {
    # Set boot
    local action="Boot node from Virtual Media Once"
    rest_result=$($CURL --globoff  -L -w "%{http_code}"  -ku ${username_password}  \
      -H "Content-Type: application/json" -H "Accept: application/json" \
      -d '{"Boot":{ "BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd" }}' \
      -o "$rest_response" -X PATCH $system_path)
    check_rest_result "$action" "$rest_result" "$rest_response"
}

check_rest_result() {
    local action=$1
    local rest_result=$2
    local rest_response=$3

    if [[ -n "$rest_result" ]] && [[ $rest_result -lt 300 ]]; then
      show_info "$action" "$rest_result"
    else
      show_warn "$action" "$rest_result"
      echo $(cat $rest_response)
    fi
    rm -f $rest_response
}

install(){
  echo "Starting OpenShift deployment on ${bmc_address}..."
  server_power_off
  sleep 15
  virtual_media_eject
  virtual_media_insert
  #virtual_media_status
  server_set_boot_once_from_cd
  sleep 10
  server_power_on
  #server_restart
  echo ""
  echo "Node is booting from virtual media mounted with $iso_image, check your BMC console to monitor the installation progress."
}

post_install(){
  virtual_media_eject
}

$cmd
