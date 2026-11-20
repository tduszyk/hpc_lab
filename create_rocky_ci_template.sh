#!/usr/bin/env bash
set -euo pipefail

# Configuration defaults (can be overwritten via environment variables)
FILENAME="Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
DIR="/var/lib/vz/templates"
URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/"
STORAGE="${STORAGE:-local-lvm}"
VM_NAME="${VM_NAME:-rocky9-tmpl}"
CI_USER="${CI_USER:-admin}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519.pub}"

# State tracking for cleanup trap
TEMP_FILE=""
CREATED_VMID=""

cleanup() {
  local exit_code=$?
  if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
    rm -f "$TEMP_FILE"
  fi
  if [[ $exit_code -ne 0 && -n "$CREATED_VMID" ]]; then
    echo "Error detected. Rolling back partially created VM ${CREATED_VMID}..." >&2
    qm destroy "$CREATED_VMID" --purge &>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
    cat >&2 <<-EOF

Usage: ${0##*/} <id> <memory> <cores> <disk_size>

Arguments: 
  id		Proxmox VM ID (eg 9000)
  memory	Memory in MiB (eg 2048)
  cores		Number of CPU cores (eg 2)
  disk_size	Disk size (eg 10G)

Example:
  ${0##*/} 9000 2048 2 10G

EOF
}

validate_args() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if (( $# != 4 )); then
    echo "Error: Expected 4 arguments, got $#." >&2
    usage
    exit 1
  fi

  local vm_id="$1" memory="$2" cores="$3" disk_size="$4"

  if ! [[ "$vm_id" =~ ^[0-9]+$ ]] || (( vm_id < 100 || vm_id > 999999999 )); then
    echo "Error: VM ID must be an integer between 100 and 999999999 (got '$vm_id')." >&2
    exit 1
  fi

  if ! [[ "$memory" =~ ^[0-9]+$ ]] || (( memory < 512 )); then
    echo "Error: Memory must be an integer >= 512 MiB (got '$memory')." >&2
    exit 1
  fi

  if ! [[ "$cores" =~ ^[0-9]+$ ]] || ((cores < 1)); then
    echo "Error: Cores must be an integer >=1 (got '$cores')." >&2
    exit 1
  fi
  
  if ! [[ "$disk_size" =~ ^\+?[0-9]+[KMGT]$ ]]; then
    echo "Error: Disk size must match format like 10G or +10G (got '$disk_size')." >&2
    exit 1
  fi
}

preflight_checks() {
}

download() {
    	local target_file="${DIR%/}/${FILENAME}"
    	local temp_file="${target_file}.part"
    	local checksum_url="${URL%/}/${FILENAME}.CHECKSUM"

    	# 1. Ensure the target directory exists
    	if ! mkdir -p "$DIR"; then
        	echo "Error: Failed to create or access directory $DIR" >&2
        	return 1
    	fi

    	# 2. Fetch the official SHA256 checksum first to check if we already have the exact version
    	local expected_sha256
    	expected_sha256=$(curl -fsSL "$checksum_url" | awk '/SHA256/ {print $NF}')
    
    	if [[ -z "$expected_sha256" ]]; then
        	echo "Error: Could not retrieve remote checksum from $checksum_url" >&2
        	return 1
    	fi

    	# 3. Check if file exists AND matches the latest remote checksum
    	if [[ -f "$target_file" ]]; then
        	local local_sha256
        	local_sha256=$(sha256sum "$target_file" | awk '{print $1}')
        	if [[ "$local_sha256" == "$expected_sha256" ]]; then
            		echo "Latest image already exists and passed SHA256 verification."
            		return 0
        	else
            		echo "Local image is outdated or corrupted. Re-downloading..."
        	fi
    	fi

    	# 4. Download to a .part file first, then atomically rename upon success
    	echo "Downloading ${FILENAME}..."
    	if ! wget -q --show-progress -O "$temp_file" "${URL%/}/${FILENAME}"; then
        	echo "Error: Download failed." >&2
        	rm -f "$temp_file"
        	return 1
    	fi

    	# 5. Verify checksum of the newly downloaded file before moving it into place
    	local downloaded_sha256
    	downloaded_sha256=$(sha256sum "$temp_file" | awk '{print $1}')
    	if [[ "$downloaded_sha256" != "$expected_sha256" ]]; then
        	echo "Error: Checksum mismatch! Expected $expected_sha256, got $downloaded_sha256" >&2
        	rm -f "$temp_file"
        	return 1
    	fi

    	mv -f "$temp_file" "$target_file"
    	echo "Download verified and saved to $target_file."
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

main(){
  validate_args
  preflight_checks
  download
  deploy_vm
}

main
