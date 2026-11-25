#!/usr/bin/env bash
set -euo pipefail
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
MEM_AVAIL=$(awk '/MemAvailable/ {print $2 " kB"}' /proc/meminfo)
DISK_USE=$(df -h / | awk 'NR==2 {print $5}')
echo "HEALTH_CHECK host=$(hostname) load=[${LOAD}] mem_avail=${MEM_AVAIL} root_use=${DISK_USE}"
