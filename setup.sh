#! /usr/bin/env bash

#  --------------------------------------------------------------------------------------------------------------------
#
#  Install & Configure a PXE boot server with Canonical Multipass
#
#  For a detailed explanation, see the documentation at:
#  Documents/IT/Infrastructure/DDI/IPv4 UEFI PXE Boot Server based on multipass.md
#
#
#  2025-02-15
#
#  scripts.bash@brigehead.it
#
#  --------------------------------------------------------------------------------------------------------------------


#  TODO
#  Check if the $instance_files is necessary, or if that could be done with $tmp



#  --------------------------------------------------------------------------------------------------------------------
#  PROPERTIES
#  --------------------------------------------------------------------------------------------------------------------


#instance_ip  #  will be determined by Multipass at first start
instance_name=pxe-boot-server
instance_files="$HOME/.config/multipass/$instance_name"
#cloud_init_files="$HOME/Scripts/bash/debian/config/ubuntu/user-data-multipass"
local_network='192.168.254.0'
local_gateway='192.168.254.254'
domain='internal'
server_fqdn=${instance_name}.${domain}

pxe_boot_file=bootx64.efi



#  --------------------------------------------------------------------------------------------------------------------
#  CONFIGURE MULTIPASS
#  --------------------------------------------------------------------------------------------------------------------


#  enable Multipass to bridge the local instances network interfaces
#  to that network interface of the host, that provides internet access
#
#  do not do this indiscriminately, as the multipassd will sometimes hang afterwards
#  fix problems with a reboot or `launchctl bootout ...`
if [[ ! $(multipass get local.bridged-network) ]]
then multipass set local.bridged-network=$(netstat -rnf inet | sed -n 's/.* UG.* \([a-z].*\)/\1/p')
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
#####################multipass exec "$instance_name" -- sudo apt-get --update --auto-remove --purge --yes full-upgrade
multipass exec "$instance_name" -- sudo reboot

#  the IP is only available now, after the Multipass instance has started once and been assigned its' IPv4's by the host.
while [[ -z "$instance_ip" ]]
do
    sleep 1
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

	subnet $local_network netmask 255.255.255.0 {
	    option routers $local_gateway;
	    option domain-name-servers 127.0.0.1;
	    range ${local_network::-2}.4 ${local_network::-2}.6;

	    #  IPv4 address of the TFTP service which PXE clients should connect to
	    #  == the address of the this Multipass instance network interface, that connects to the local network
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
multipass exec "$instance_name" -- bash -c "sudo tee /etc/default/tftpd-hpa > /dev/null <<- EOF
	TFTP_USERNAME=tftp
	TFTP_DIRECTORY=$(multipass exec "$instance_name" -- pwd)/$instance_name
	TFTP_ADDRESS=:69
	TFTP_OPTIONS=--secure
EOF"
#  enable and start
multipass exec "$instance_name" -- sudo systemctl --quiet --now enable tftpd-hpa
#  check
multipass exec "$instance_name" -- sudo systemctl status tftpd-hpa



#  --------------------------------------------------------------------------------------------------------------------
#  WEB SERVICE
#  --------------------------------------------------------------------------------------------------------------------


#  install
multipass exec "$instance_name" -- sudo apt --yes install apache2
#  configure
multipass exec "$instance_name" -- bash -c "sudo tee /etc/apache2/sites-available/${instance_name}.conf > /dev/null <<- EOF
	<VirtualHost *:80>
	    ServerName $server_fqdn

	    ErrorLog  ${APACHE_LOG_DIR}/${server_fqdn/./_}-error_log
	    CustomLog ${APACHE_LOG_DIR}/${server_fqdn/./_}-access_log common

	    <Directory /var/www/html/cloud-init>
	        Options Indexes MultiViews
	        AllowOverride All
	        Require all granted
	    </Directory>

	    <Directory /var/www/html/repository>
	        Options Indexes MultiViews
	        AllowOverride All
	        Require all granted
	    </Directory>
	</VirtualHost>
EOF"
#  enable and start
multipass exec "$instance_name" -- sudo systemctl --quiet --now enable apache2
#  check
multipass exec "$instance_name" -- sudo systemctl status apache2
open http://$instance_ip/cloud-init
