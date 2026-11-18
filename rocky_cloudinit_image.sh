#!/usr/bin/env bash

FILENAME="Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
DIR="/var/lib/vz/templates/"
URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/"

usage() {
	cat <<-EOF
	Usage: rocky_cloudinit_image.sh id memory cores disk_size
	echo;echo;echo
	EOF
}

download() {
	if [[ ! -f "$DIR$FILENAME" ]]; then
		echo "Downloading the latest image..."; echo
		cd "$DIR"
		wget "$URL$FILENAME"
	else
		echo "The image exists on the disk."; echo
	fi
}

deploy_vm() {
	echo Creating a VM vm_id:$1 memory:$2 cpu_cores:$3 disk_size:$4
	qm create $1 --name rocky9-tmpl --memory $2 --cores $3 --cpu host \
	  --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 \
	  --scsihw virtio-scsi-single --ostype l26 --agent enabled=1
	qm disk import $1 Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 local-lvm
	qm set $1 --scsi0 local-lvm:vm-$1-disk-0,discard=on,iothread=1 --boot order=scsi0
	qm set $1 --ide2 local-lvm:cloudinit --serial0 socket --vga serial0
	qm set $1 --ciuser admin --sshkeys ~/.ssh/id_ed25519.pub --ipconfig0 ip=dhcp
	qm resize $1 scsi0 $4
	qm template $1
}

usage
download
deploy_vm
