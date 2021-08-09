#!/bin/bash

###################################
# Helper functions
###################################
PROG=$(basename $0)
function ee {
	echo "[ERROR] $PROG: $@" >&2; exit 1
}
function ei {
	echo "[INFO] $PROG: $@" >&2;
}
function ed {
	[ -n "$VERBOSE" ] && echo "[DEBUG] $PROG: $@" >&2;
}
function ew {
	echo "[WARN] $PROG: $@" >&2;
}
export -f ee ei ed ew

###################################
# Handle CLI arguments
###################################

# Default Values
VENDOR=10de
DEFAULT=
VERBOSE=
PRINT_N=

function usage {
	echo """For each NVIDIA VGA device running with the vfio-pci driver, the:

BUS SLOT FUNCTION

are printed for each device. Warns on STDERR when no devices are found.

Usage: $PROG [-h] [-V STR] [-N] [-d] [-v]

optional arguments:
 -V STR Looks for devices of the vendor [$VENDOR]
 -N     Prints the number of devices detected
 -d     Prints in default BUS:SLOT.FUNCTION format
 -v     Enable verbose logging
 -h     Print this help text""" >&2; exit 0
}

while getopts :h:VNdv flag; do
	case "${flag}" in
		V) VENDOR=${OPTARG};;
		N) PRINT_N=1;;
		d) DEFAULT=1;;
		v) VERBOSE=1;;
		:) echo -e "[ERROR] Missing an argument for ${OPTARG}\n" >&2; usage;;
		\?) echo -e "[ERROR] Illegal option ${OPTARG}\n" >&2; usage;;
		h) usage;;
	esac
done
#########################################
## This command queries for devices
CMD="lspci -nnk -d ${VENDOR}:* | grep -A 2 0300 | grep -B 2 vfio-pci | grep VGA"
#########################################
ed $(eval $CMD)
# Count the number of devices detected
ND=$(eval $CMD | cut -f 1 -d ' ' | wc -l)
# Print number of devices and exit if selected
if [ -n "$PRINT_N" ]; then
	echo ${PRINT_N}; exit 0
fi
if [ $ND -eq 0 ]; then
	# Warn if no devices detected
	ew """Detected $ND device(s)

Verify that your target GPU devices have the

    vfio-pci

driver loaded. More information can be found at

https://github.com/NVIDIA/deepops/blob/master/virtual/README.md"""
else
	ed "Detected $ND device(s)"
fi
# Print device information line by line
if [ -n "$DEFAULT" ]; then
	eval $CMD | cut -f 1 -d ' '
else
	eval $CMD | sed 's/\([0-9]\+\):\([0-9]\+\).\([0-9]\+\) .*/\1 \2 \3/'
fi
