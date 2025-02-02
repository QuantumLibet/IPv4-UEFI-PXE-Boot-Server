#! /usr/bin/env bash


instance_name='pxe-boot-server'
instance_files="$HOME/.config/multipass/$instance_name"
cloud_init_files="$HOME/Scripts/bash/debian/config/ubuntu/user-data-multipass"

#  enable Multipass to bridge the local instances network interfaces
#  to that network interface of the host, that provides internet access
multipass set local.bridged-network=$(netstat -rnf inet | sed -n 's/.* UG.* \([a-z].*\)/\1/p')

#  ensure a local folder on the host is available to store the files used by the instance
mkdir -p "$instance_files"

#  launch a Multipass instance
multipass launch  --name "$instance_name"  --bridged  --mount "$instance_files" --cloud-init "$cloud_init_files" lts

#  update the Multipass instance & restart
multipass exec "$instance_name" -- sudo apt-get --update --auto-remove --purge --yes full-upgrade
multipass restart "$instance_name"


# ====================================================================================================================


#  install the ISC DHCP server
multipass exec "$instance_name" -- sudo apt --yes install isc-dhcp-server


local_network='192.168.254.0'
local_gateway='192.168.254.254'
local_ip=

cat > dhcpd.conf << EOF
#  DHCP server properties
#allow bootp;    #  default
#allow booting;  #  default
max-lease-time 1200;
default-lease-time 900;
abandon-lease-time 120;  #  make ips available to clients after 120 sec
log-facility local7;

#  DHCP protocol options
option ip-forwarding false;
option mask-supplier false;

subnet $local_network netmask 255.255.255.0 {
    option routers $local_gateway;
    option domain-name-servers 127.0.0.1;
    range ${local_network::-1}.4 ${local_network::-1}.6;
    filename "bootx64.efi";  #  the initial boot file to load by a client
    next-server $local_ip;   #  address of the server from which the initial boot file is to be loaded
}
EOF
