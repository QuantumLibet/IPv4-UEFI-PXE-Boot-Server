#! /usr/bin/env bash

#  --------------------------------------------------------------------------------------------------------------------
#
#  Install & Configure a PXE boot server with Canonical Multipass
#
#  For a detailed explanation, see the documentation at:
#  ~/Documents/IT/Infrastructure/DDI/IPv4 UEFI PXE Boot Server based on multipass.md
#
#
#  2025-03-01
#
#  scripts.bash@brigehead.it
#
#  --------------------------------------------------------------------------------------------------------------------





#  --------------------------------------------------------------------------------------------------------------------
#  PROPERTIES
#  --------------------------------------------------------------------------------------------------------------------


#instance_ip  #  will be determined (further down this script) by Multipass at first start
instance_name=pxe-boot-server
instance_files="$HOME/.config/multipass/$instance_name"
#cloud_init_files="$HOME/Scripts/bash/debian/config/ubuntu/user-data-multipass"

local_subnet='192.168.254'  #  last octet is missing by design
local_gateway='192.168.254.254'
domain='internal'  #  as defined by https://datatracker.ietf.org/doc/html/draft-davies-internal-tld-02, 2025-02-02
server_fqdn=${instance_name}.${domain}

pxe_boot_file=bootx64.efi



#  --------------------------------------------------------------------------------------------------------------------
#  CONFIGURE MULTIPASS
#  --------------------------------------------------------------------------------------------------------------------


#  enable Multipass to bridge the instance's network interface
#  to the host's network interface, which provides internet access
#
#  this might cause `multipassd` to hang
#  fix with a reboot of the host, or `sudo --askpass launchctl bootout system /Library/LaunchDaemons/com.canonical.multipassd.plist` and `bootstrap`
if [[ "$(multipass get local.bridged-network)" == "<empty>" ]]
then multipass set local.bridged-network="$(netstat -rnf inet | sed -n 's/.* UG.* \([a-z].*\)/\1/p')"
fi



#  --------------------------------------------------------------------------------------------------------------------
#  CREATE MULTIPASS INSTANCE
#  --------------------------------------------------------------------------------------------------------------------


#  ensure a local folder on the host is available to store the files used by the instance
mkdir -p "$instance_files"

#  create user-data cloud-init file to rename the instance
cat > "$instance_files/user-data-multipass" <<- EOF
	#cloud-config
	runcmd:
	  - hostnamectl hostname $instance_name
EOF

#  launch a Multipass instance
multipass launch  --name "$instance_name"  --bridged  --mount "$instance_files" --cloud-init "$instance_files/user-data-multipass" lts
#multipass launch  --name "$instance_name"  --bridged  --mount "$instance_files" --cloud-init "$cloud_init_files" lts

#  update the Multipass instance & restart
multipass exec "$instance_name" -- sudo apt-get --update --auto-remove --purge --yes full-upgrade
multipass exec "$instance_name" -- sudo reboot

#  the IP is only available now, after the Multipass instance has started once and been assigned its' IPv4's by the host.
while [[ -z "$instance_ip" ]]
do
    sleep 10
    instance_ip=$(multipass ls | awk -v instance="$instance_name" '$1 == instance && $2 == "Running" {getline; print $NF}')
done
sleep 1



#  --------------------------------------------------------------------------------------------------------------------
#  DHCP SERVICE
#  --------------------------------------------------------------------------------------------------------------------


#  install
multipass exec "$instance_name" -- sudo apt --yes install isc-dhcp-server
#  configure
multipass exec "$instance_name" -- bash -c "sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<- EOF
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

	subnet ${local_subnet}.0 netmask 255.255.255.0 {
	    option routers $local_gateway;
	    option domain-name-servers 127.0.0.1;
	    range ${local_subnet}.4 ${local_subnet}.6;

	    #  IPv4 address of the TFTP service which PXE clients should connect to
	    #  == the address of the this Multipass instance's network interface, that connects to the local network
	    next-server $(multipass ls | awk -v instance="$instance_name" '$1 == instance && $2 == "Running" {getline; print $NF}');

	    #  filename of the initial boot file which PXE clients should request from the TFTP service
	    filename \"$pxe_boot_file\";
}
EOF"
#  enable and start
multipass exec "$instance_name" -- sudo systemctl --quiet --now enable isc-dhcp-server.service
#  check
multipass exec "$instance_name" -- sudo systemctl status isc-dhcp-server.service



#  --------------------------------------------------------------------------------------------------------------------
#  TFTP SERVICE
#  --------------------------------------------------------------------------------------------------------------------


#  install
multipass exec "$instance_name" -- sudo apt --yes install tftpd-hpa
#  configure
multipass exec "$instance_name" -- sudo sed -i "s|\(TFTP_DIRECTORY=\"\).*\(.\)$|\1$(multipass exec $instance_name -- pwd)/$instance_name/tftp\"|" /etc/default/tftpd-hpa
#  enable and start
multipass exec "$instance_name" -- sudo systemctl --quiet --now enable tftpd-hpa
#  check
multipass exec "$instance_name" -- sudo systemctl status tftpd-hpa



#  --------------------------------------------------------------------------------------------------------------------
#  WEB SERVICE
#  --------------------------------------------------------------------------------------------------------------------


#  install
multipass exec "$instance_name" -- sudo apt --yes install lighttpd
#  configure
multipass exec "$instance_name" -- sudo sed -i "s|\(server.document-root .*= \"\).*\(.\)$|\1$(multipass exec $instance_name -- pwd)/$instance_name/http\"|" /etc/lighttpd/lighttpd.conf
#  enable and start
multipass exec "$instance_name" -- sudo systemctl --quiet --now enable lighttpd
#  check
multipass exec "$instance_name" -- sudo systemctl status lighttpd



#  --------------------------------------------------------------------------------------------------------------------
#  PROVISION FILES
#  --------------------------------------------------------------------------------------------------------------------


git clone --depth=1 https://github.com/QuantumLibet/IPv4-UEFI-PXE-Boot-Server.git
sudo rsync --archive IPv4-UEFI-PXE-Boot-Server/tftp/ /srv/tftp/
sudo rsync --archive IPv4-UEFI-PXE-Boot-Server/html/ /var/www/html/

open "http://$instance_ip/cloud-init"
