#!/bin/sh

#This script has been modified from an example
vm_name="debian-vm"
vm_dir="/home/Administrator/vms/"
iso_cd0="${vm_dir}/debian-installer.iso"

vm_bridge0="bridge0"
vnc_port="5900"
nic_port="em1"
efi_vars="${vm_dir}/EFI_VARS.fd"
vm::init(){
	kldload vmm
}

err(){
    echo "Error: ${1}" 1>&2
    exit 1
}

vm::config(){
	
	if [ ! -f "${efi_vars}" ]; then
                cp /usr/local/share/uefi-firmware/BHYVE_BHF_UEFI_VARS.fd "${efi_vars}"
	fi
	
	ifconfig ${vm_bridge}
	if [$? -ne 0]; then
		ifconfig bridge create name ${vm_bridge}
	fi

	_tap0="$(ifconfig tap create)"
	sysctl net.link.tap.up_on_open=1 #enable the tap interface
	sysctl net.link.bridge.pfil_member=0 #enable communication through the firewall to members of the bridge interface

	# bridge device is created via cloned interfaces in rc.conf
	#this line issues the command to add the tap0 and em1 interfaces as members of bridge0.
	#This will allow communication on the em1 interface to be sent to the tap0 interface where the vm will be able to receive it
	ifconfig bridge0 addm tap0 addm ${nic_port}
	
	
	
}

vm::run(){

	while true; do
	
		if [ "${install_os}" == "true" ]; then #if the caller has indeicated that this is an installation run.
                	_installerdisk="-s 10:0,ahci-cd,${iso_cd0}"
        	else
                	_installerdisk=""
        	fi

		bhyve -c 2 -m 1G \
		-A -H \
		-l bootrom,/usr/local/share/uefi-firmware/BHYVE_BHF_UEFI.fd,"${efi_vars},fwcfg=qemu" \
		-s 0:0,hostbridge \
		-s 1:0,virtio-blk,/dev/zvol/zroot/debian-vm_disk0 \
		-s 2:0,virtio-net,tap0 \
		${_installerdisk} \
		-s 29:0,fbuf,tcp=0.0.0.0:"${vnc_port}",w=1024,h=768,wait \
		-s 30:0,xhci,tablet \
		-s 31:0,lpc \
		debian-vm

		_rc=$?
	
	# see man 8 bhyve for definition of bhyve return codes
		if [ ${_rc} -ne 0 ]; then
			break
		fi
		
		if [ "${install_os}" == "true" ]; then		
			install_os="false"
			_installerdisk=""
		fi 
		
	done
	
}

vm::destroy(){
	bhyvectl --vm=${vm_name} --destroy
	sleep 1
}

vm::cleanup(){

	if [ -f bhyve.pid ]; then
		rm bhyve.pid
	fi

	if [ -n "$(ifconfig tap0)"  ]; then
		ifconfig bridge0 deletem tap0 deletem ${nic_port}
		ifconfig tap0 destroy 
	fi

}

#Main script instructions
if [ $(id -u) -ne 0 ]; then
    err "${0##*/} must be run as root!"
fi


install_os="false"

for _arg in $@; do
	case ${_arg} in
		--install)
			install_os="true"
			break
		;;
	esac
done

if [ $# -lt 1 ]; then
    err "No Commands Provided"
fi

case $1 in
	config)
		vm::config
		;;
	run)
		vm::init
		vm::run
		;;
	destroy)
		vm::destroy
		vm::cleanup
		;;
esac

