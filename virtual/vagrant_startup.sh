#!/usr/bin/env bash

. /etc/os-release
# Get absolute path for script, and convenience vars for virtual and root
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
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
# Default Values
###################################
export VAGRANT_VERSION=2.2.16
export VERBOSE=
export SKIP_DEPS=
# OS values
export SUPPORTED_DIST=( ubuntu centos )
export SUPPORTED_OS=( ubuntu1804 ubuntu2004 centos7 centos8 )
export OS_DIST=ubuntu
export OS_VERSION=2004
# Management values
export N_MGMT_VM=1
export MGMT_CPU=2
export MGMT_MEM=4096
# Login values
export N_LOGIN_VM=1
export LOGIN_CPU=2
export LOGIN_MEM=4096
# Compute values
export GPUS_PER_VM=1
export N_GPUS=$(${VIRT_DIR}/scripts/get_passthrough_gpus.sh -N)
export N_GPU_VM=$(( $N_GPUS / $GPUS_PER_VM ))
export N_CPU_VM=0
export GPU_CPU=2
export GPU_MEM=4096
###################################
# Handle CLI arguments
###################################
function usage {
  echo """Create a Vagrant cluster for testing DeepOps deployment

Usage: $PROG [-h] [-v] [-s] [-O STR] [-V STR]
             [-G INT] [-N INT] [-C INT] [-x INT]
             [-M INT] [-m INT] [-y INT]
             [-L INT] [-l INT] [-z INT]

optional OS related arguments:
 -O STR OS Distribution [${OS_DIST}]
        Supported options: {${SUPPORTED_DIST[@]}}
 -V STR OS Version [${OS_VERSION}]
        Supported versions:
          - ubuntu {1804, 2004}
          - centos {7, 8}

optional compute node VM arguments:
 -G INT GPUs per VM [${GPUS_PER_VM}]
 -N INT Number of compute VMs [${N_GPU_VM}]
        Increasing this beyond the number of GPUs
        will create CPU-only nodes.
 -C INT CPUs per compute VM [${GPU_CPU}]
 -x INT MB RAM per compute VM [${GPU_MEM}]

optional management VM arguments:
 -M INT Number of management VMs [${N_MGMT_VM}]
 -m INT Number CPUs per management VM [${MGMT_CPU}]
 -y INT MB RAM per management VM [${MGMT_MEM}]

optional login VM arguments:
 -L INT Number of login VMs [${N_LOGIN_VM}]
 -l INT Number CPUs per login VM [${LOGIN_CPU}]
 -z INT MB RAM per login VM [${LOGIN_MEM}]

optional arguments:
 -s     Skip dependency check
 -v     Enable verbose logging
 -d     Enable Vagrant debug logging
 -h     Print this help text""" >&2; exit 0
}

while getopts :hdvsO:V:G:N:C:x:M:m:y:L:l:z: flag; do
  case "${flag}" in
    O) export OS_DIST=${OPTARG};;
    V) export OS_VERSION=${OPTARG};;
    G) export GPUS_PER_VM=${OPTARG};;
    N) export N_GPU_VM=${OPTARG};;
    C) export GPU_CPU=${OPTARG};;
    x) export GPU_MEM=${OPTARG};;
    M) export N_MGMT_VM=${OPTARG};;
    m) export MGMT_CPU=${OPTARG};;
    y) export MGMT_MEM=${OPTARG};;
    L) export N_LOGIN_VM=${OPTARG};;
    l) export LOGIN_CPU=${OPTARG};;
    z) export LOGIN_MEM=${OPTARG};;
    s) export SKIP_DEPS=1;;
    v) export VERBOSE=1;;
    d) export VAGRANT_LOG=debug;;
    :) echo -e "[ERROR] Missing an argument for ${OPTARG}\n" >&2; usage;;
    \?) echo -e "[ERROR] Illegal option ${OPTARG}\n" >&2; usage;;
    h) usage;;
  esac
done
###################################
# Check options
###################################

# Make sure the distribution is supported
export FULL_OS=${OS_DIST}${OS_VERSION}
ed "Using ${FULL_OS} for VM OS"
if [[ ! " ${SUPPORTED_OS[@]} " =~ " ${FULL_OS} " ]]; then
  ee "${FULL_OS} is not a supported distribution and version combination"
fi

# Make sure there are enough GPUs for at least one VM
if [ "${GPUS_PER_VM}" -lt "${N_GPUS}" ]; then
  ee "${GPUS_PER_VM} GPUs were requested per VM, and only ${N_GPUS} are available"
fi

# Warn if oversubscribing CPUs
export N_CPUS=$(nproc --all)
export N_REQUESTED_CPUS=$(( ${N_MGMT_VM}*${MGMT_CPU} + ${N_LOGIN_VM}*${LOGIN_CPU} + ${N_GPU_VM}*${GPU_CPU} ))
if [ "${N_REQUESTED_CPUS}" -gt "${N_CPUS}" ]; then
  ew "Your configuration consumes ${N_REQUESTED_CPUS}, but only ${N_CPUS} are detected"
fi

# Make sure there's a compute node
if [ "${N_GPU_VM}" -lt "1" ]; then
  ee "${N_GPU_VM} compute nodes requested. Please specify at least one"
fi

#####################################
# Install Vagrant and Dependencies
#####################################
export YUM_DEPENDENCIES="centos-release-qemu-ev qem-kvm-ev qemu-kvm \
    libvirt virt-install bridge-utils libvirt-devel libxslt-devel \
    libxml2-devel libguestfs-tools-c sshpass qemu-kvm libvirt-bin \
    libvirt-dev bridge-utils libguestfs-tools qemu virt-manager firewalld OVMF openssh-server"
export APT_DEPENDENCIES="build-essential sshpass qemu-kvm libvirt-bin \
    libvirt-dev bridge-utils libguestfs-tools qemu ovmf virt-manager firewalld ssh"

function install_vagrant_plugins {
  ed "Detected $(vagrant --version)"
  [ -n "$SKIP_DEPS" ] && return
  for plugin in libvirt sshfs host-shell scp mutate; do
    pname=vagrant-${plugin}
    if vagrant plugin list | grep -q ${pname}; then
      ed "Vagrant plugin $pname already installed"
    else
      vagrant plugin install $pname
    fi
  done
}
function check_libvirtd {
  # Ensure libvirtd is running
  if ! sudo systemctl is-active --quiet libvirtd; then
    ed "Enabling the libvirtd daemon"
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
  fi
}
function add_user_libvirt {
  if ! groups "$USER" | grep "${LIBVIRT_GROUP}" &> /dev/null; then
    ew "Adding your user to ${LIBVIRT_GROUP} so you can manage VMs."
    ew "You may need to start a new shell to use vagrant interactively."
    sudo usermod -a -G ${LIBVIRT_GROUP} $USER
  fi
}

case "$ID" in
  rhel*|centos*)
    # Install Vagrant & Dependencies for RHEL Systems
    # shellcheck disable=SC2086
    if ! (yum grouplist installed | grep "Development Tools" && rpm -q $YUM_DEPENDENCIES) >/dev/null 2>&1; then
      echo "Installing yum dependencies..."

      sudo yum group install -y "Development Tools"
      # shellcheck disable=SC2086
      sudo yum install -y $YUM_DEPENDENCIES
    fi

    # Optional set up networking for Vagrant VMs. Uncomment and adjust if needed
    #sudo echo "net.ipv4.ip_forward = 1"|sudo tee /etc/sysctl.d/99-ipforward.conf
    #sudo sysctl -p /etc/sysctl.d/99-ipforward.conf

    # Ensure we have permissions to manage VMs
    export LIBVIRT_GROUP="libvirt"
    add_user_libvirt

    # Ensure libvirtd is running
    check_libvirtd

    # Install Vagrant
    if ! which vagrant >/dev/null 2>&1; then
      # install vagrant (frozen at 2.2.3 to avoid various issues)
      pushd "$(mktemp -d)"
      wget https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.rpm -O vagrant.rpm
      #sudo rpm -i vagrant.rpm
      sudo yum -y localinstall vagrant.rpm
      popd

    fi
    # install vagrant plugins
    install_vagrant_plugins
    # End Install Vagrant & Dependencies for RHEL Systems
    ;;

  ubuntu*)
    # No interactive prompts from apt during this process
    export DEBIAN_FRONTEND=noninteractive
    # Install Vagrant & Dependencies for Debian Systems


    # Ensure we have permissions to manage VMs
    case "${VERSION_ID}" in
      18.*)
        export LIBVIRT_GROUP="libvirt";;
      20.*)
        export LIBVIRT_GROUP="libvirt"
        export APT_DEPENDENCIES="build-essential sshpass qemu-kvm libvirt-daemon-system \
          libvirt-dev bridge-utils libguestfs-tools qemu ovmf virt-manager firewalld ssh";;
      *)
        export LIBVIRT_GROUP="libvirtd"
    esac

    # shellcheck disable=SC2086
    if ! (dpkg -s $APT_DEPENDENCIES) >/dev/null 2>&1; then
      echo "Installing apt dependencies..."

      # Update apt
      sudo apt-get update -y

      # Install build-essential tools
      # shellcheck disable=SC2086
      sudo apt-get install -y $APT_DEPENDENCIES
    fi

    add_user_libvirt
    
    # Ensure libvirtd is running
    check_libvirtd

    # Install Vagrant
    if ! which vagrant >/dev/null 2>&1; then
      pushd "$(mktemp -d)"
      wget https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.deb -O vagrant.deb
      sudo dpkg -i vagrant.deb
      popd
    fi
    # install vagrant plugins
    install_vagrant_plugins
    # End Install Vagrant & Dependencies for Debian Systems
    ;;
  *)
    ew "Unsupported Operating System $ID_LIKE"
    ee "You are on your own to install Vagrant and build a Vagrantfile then you can manually start the DeepOps virtual setup"
    ;;
esac

#####################################
# Set up VMs for virtual cluster
#####################################
export DEEPOPS_PATH=$(dirname ${VIRT_DIR})
OS_VARS='${OS_DIST} ${OS_VERSION} ${DEEPOPS_PATH}'
MGMT_VARS='${N_MGMT_VM} ${MGMT_CPU} ${MGMT_MEM}'
LOGIN_VARS='${N_LOGIN_VM} ${LOGIN_CPU} ${LOGIN_MEM}'
GPU_VARS='${GPUS_PER_VM} ${N_GPUS} ${N_GPU_VM} ${GPU_CPU} ${GPU_MEM}'
ALL_VARS="${OS_VARS} ${MGMT_VARS} ${LOGIN_VARS} ${GPU_VARS}"

# Ensure we're in the right directory for Vagrant
cd "${VIRT_DIR}" || exit 1

# Destroy old vagrant cluster before creating new Vagrantfile
newgrp "${LIBVIRT_GROUP}" << RM_VMS
  if [ -e Vagrantfile ]; then
    ed "Detected an old Vagrantfile, attempting to destroy deployment..."
    vagrant destroy -f
  fi
RM_VMS

# Create the vagrantfile
envsubst "${ALL_VARS}" < ${VIRT_DIR}/Vagrantfile.tmpl > ${VIRT_DIR}/Vagrantfile

# Create SSH key in default location if it doesn't exist
if [ ! -e ~/.ssh/id_rsa ]; then
  ed "Creating ~/.ssh/id_rsa"
  ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -C "" -N ""
fi

# Allow connections to libvirt cluster through firewall
ed "Allowing all connections from libvirt (192.168.121.0/24) through your firewall"
ed $(sudo firewall-cmd --zone=trusted --add-source=192.168.121.0/24 2>&1)

ei """Creating the following VMs running ${OS_DIST}${OS_VERSION}:
- ${N_MGMT_VM} management VMs [${MGMT_CPU} CPU, ${MGMT_MEM} MB RAM]
- ${N_LOGIN_VM} login VMs [${LOGIN_CPU} CPU, ${LOGIN_MEM} MB RAM]
- $(( $N_GPUS / $GPUS_PER_VM )) gpu VMs [${GPU_CPU} CPU, ${GPUS_PER_VM} GPU, ${GPU_MEM} MB RAM]
- $(( $N_GPUS / $GPUS_PER_VM - ${N_GPU_VM} )) cpu VMs [${GPU_CPU} CPU, ${GPU_MEM} MB RAM]"""

# Ensure we're using the libvirt group during vagrant up
newgrp "${LIBVIRT_GROUP}" << MAKE_VMS
  # Make sure our environment is clean
  vagrant global-status --prune

  # Start vagrant via libvirt - set up the VMs
  set -e
  vagrant up --provider=libvirt

  # Show the running VMs
  virsh list
MAKE_VMS

# Make inventory file
if command -v python3 &> /dev/null; then
  ed "Generating inventory with python3"
  python3 scripts/generate_inventory.py
else
  ed "Generating inventory with python"
  python scripts/generate_inventory.py
fi

# Create config.virtual
CE=${VIRT_DIR}/../config.example
CV=${VIRT_DIR}/../config
[ ! -e $CE ] && ee "The deepops/config.example directory doesn't seem to exist"
if [ ! -e $CV ]; then
  ei "Creating config from config.example"
  cp -r $CE $CV
  ed "Linking virtual inventory to config"
  ln -fs ../virtual/inventory ${CV}/inventory
  ed "Injecting vars from deepops/virtual/vars_files"
  grep -v '\-\-\-\+' vars_files/virt_k8s.yml >> ${CV}/group_vars/k8s-cluster.yml
  grep -v '\-\-\-\+' vars_files/virt_slurm.yml >> ${CV}/group_vars/slurm-cluster.yml
  ei "You can reset this configuration by deleting deepops/config.virtual and redeploying"
fi
[ ! -L ${CV}/inventory ] && ew "Existing config inventory is not linked to the virtual inventory. Please delete and re-run or link the current inventory 'ln -s ../virtual/inventory ../config/inventory'"
