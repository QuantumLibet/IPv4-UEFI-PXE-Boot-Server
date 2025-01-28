#! /usr/bin/env bash


instance_name='pxe-boot-server'
instance_files="$HOME/.config/$instance_name"
cloud_init_files="$HOME/Scripts/bash/debian/config/ubuntu/user-data-multipass"

#  enable Multipass to bridge the local instances network interfaces
#  to that network interface of the host, that provides internet access
multipass set local.bridged-network=$(netstat -rnf inet | sed -n 's/.* UG.* \([a-z].*\)/\1/p')

#  ensure a local folder on the host is available to store the files used by the instance
mkdir -p "$instance_files"

#  launch a Multipass instance
multipass launch  --bridged  --mount "$instance_files":~  --name "$instance_name" --cloud-init "$cloud_init_files" lts
