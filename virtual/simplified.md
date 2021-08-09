# DeepOps Virtual

Set up a virtual cluster with DeepOps. Useful for...

1. Learning how to deploy DeepOps on limited hardware
2. Testing new features in DeepOps
3. Tailoring DeepOps in a local environment before deploying it to the production cluster

## Requirements

### Hardware Requirements

The host machine should have enough resources to fulfill the minimum VM needs...

Total: 8 vCPU, 22 GB RAM, 96 GB Storage
* virtual-login01: 2 vCPU, 6GB RAM and 32GB Storage
* virtual-mgmt01: 2 vCPU, 2GB RAM and 32GB Storage
* virtual-gpu01: 2 vCPU, 6GB RAM and 32GB Storage

If deploying kubeflow or another resource-intensive application in this environment, more vCPU, RAM, and storage resources must be allocated to virtual-mgmt01 especially.

### Operating System Requirements

* Ubuntu 18.04 (or greater)
* CentOS 7.6 (or greater)

Running DeepOps virtually assumes that the host machine's OS is an approved OS. If this is not the case, the scripts used in the steps below may be modified to work with a different OS.

Also, using VMs and optionally GPU passthrough assumes that the host machine has been configured to enable virtualization in the BIOS. For instructions on how to accomplish this, refer to the sections at the bottom of this README: [Enabling virtualization and GPU passthrough](#enabling-virtualization-and-gpu-passthrough).

## Start the Virtual Cluster

1. (Optional) Verify that your GPUs are [configured for passthrough](#enabling-virtualization-and-gpu-passthrough).

   ```sh
   $ ./scripts/get_passthrough_gpus.sh -v
   [DEBUG] get_passthrough_gpus.sh: 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117GLM [Quadro T1000 Mobile] [10de:1fb9] (rev a1)
   [DEBUG] get_passthrough_gpus.sh: Detected 1 device(s)
   01 00 0
   ```

   Any GPUs detected by this script will automatically be passed into the Vagrant cluster.
   
   > Note: This step is optional and only necessary for testing GPU-specific features

2. In the deepops/virtual directory, startup vagrant using `startup.sh`. This will start 3 VMs by default.

   ```sh
   # Print full help text
   ./startup.sh -h
   
   # Start cluster (you will be prompted for sudo password
   ./startup.sh
   ```

   This deepops repository will be mounted by nfs on every `mgmt` node for easy development in a clean environment.

3. Connect to management node and change to the deepops directory.
   
   ```sh
   host$ vagrant ssh virtual-mgmt01

   virtual-mgmt01$ cd ~/deepops
   ```

4. From the main deepops directory, run the setup script to install dependencies.

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](/docs/ANSIBLE.md).

   ```sh
   ./scripts/setup.sh
   ```

## Using the Virtual Cluster

Both the `deepops/config` and `deepops/config/inventory` are created by `startup.sh`, so you'll be able to run playbooks without any additional configuration.

### SLURM

Follow the [Slurm Deployment Guide](/docs/slurm-cluster/README.md) and then consult the [Slurm Usage Guide](/docs/slurm-cluster/slurm-usage.md) for examples of how to use SLURM.

### Kubernetes

Follow the [Kubernetes Deployment Guide](/docs/k8s-cluster/README.md) and then consult the [Kubernetes Usage Guide](/docs/k8s-cluster/kubernetes-usage.md) for examples of how to use Kubernetes.

### Connecting to the VMs

All running VMs can be listed with

```sh
# NOTE: Must be in the `deepops/virtual` directory

$ vagrant status
Current machine states:

virtual-mgmt01            running (libvirt)
virtual-login01           running (libvirt)
virtual-gpu01             running (libvirt)

This environment represents multiple VMs. The VMs are all listed
above with their current state. For more information about a specific
VM, run `vagrant status NAME`.
```

Connect to any of the running VM nodes directly via `vagrant ssh`

```sh
# NOTE: Must be in the `deepops/virtual` directory

$ vagrant ssh virtual-gpu01
```

## Destroy the Virtual Cluster

To destroy the cluster and shutdown the VMs, run the `vagrant_shutdown.sh` script...

```sh
$ ./vagrant_shutdown.sh
```

or

```sh
$ vagrant destroy -f
```

Check that there are no running VMs using `virsh list`...

```sh
$ virsh list --all
 Id    Name                           State
----------------------------------------------------
```

## Other Customization

The default Vagrantfiles create VMs that are very minimal in terms of resources to maximize where a virtual DeepOps cluster can be run. To run resource-intensive Kubernetes applications such as Kubeflow, it's necessary to increase some of the settings.

### Increase CPUs, memory, and GPUs

Resources can be increased with `vagrant_startup.sh`

```
Usage: vagrant_startup.sh [-h] [-v] [-s] [-O STR] [-V STR]
             [-G INT] [-N INT] [-C INT] [-x INT]
             [-M INT] [-m INT] [-y INT]
             [-L INT] [-l INT] [-z INT]

optional OS related arguments:
 -O STR OS Distribution [ubuntu]
        Supported options: {ubuntu centos}
 -V STR OS Version [2004]
        Supported versions:
          - ubuntu {1804, 2004}
          - centos {7, 8}

optional compute node VM arguments:
 -G INT GPUs per VM [1]
 -N INT Number of compute VMs [1]
        Increasing this beyond the number of GPUs
        will create CPU-only nodes.
 -C INT CPUs per compute VM [2]
 -x INT MB RAM per compute VM [4096]

optional management VM arguments:
 -M INT Number of management VMs [1]
 -m INT Number CPUs per management VM [2]
 -y INT MB RAM per management VM [4096]

optional login VM arguments:
 -L INT Number of login VMs [1]
 -l INT Number CPUs per login VM [2]
 -z INT MB RAM per login VM [4096]

optional arguments:
 -s     Skip dependency check
 -v     Enable verbose logging
 -d     Enable Vagrant debug logging
 -h     Print this help text
```

Helpful tips:

1. For Kubernetes clusters, we suggest increasing the memory to 16384 (`-y 16384`) and CPUs to 8 (`-m 8`) on the management VMs.
2. Exclude the `virtual-login01` VM (`-L 0`). Unless you are running slurm, this is not necessary and just takes up resources.
3. Increase the cpus for the `virtual-gpu01` VM. Suggested - v.cpus = 8.

> NOTE: The amount of CPUs and memory on your host system will vary. Change the amounts above accordingly to values that make sense.

### Increase Disk Space

1. Add v.machine_virtual_size = 100 to the Vagrantfile (Vagrantfile-<os_type>). This parameter should go under each libvirt section per node. The units are GBs, so in this case 100 GB are allocated per node.
2. `vagrant ssh` to each machine (ex: `vagrant ssh virtual-gpu01`)  and do the following...
```sh
# run fdisk
sudo fdisk /dev/sda
# d, 3, n, p, 3, enter, enter, no, p, w
```

```sh
# resize
sudo resize2fs /dev/sda3
```

```sh
# double-check that the disk size increased
df -h /
```

### Larger Clusters

The default configuration deploys a single node for each: login, management, and compute.
To run multi-node Deep Learning jobs or to test our Kubernetes HA it's necessary to deploy multiple nodes.

A cluster with the following specifications

| Function | Quantity | CPUs | GPUs | Memory |
|:--------:|:--------:|:----:|:----:|:------:|
| Management | 3 | 2 | 0 | 2G |
| Login | 1 | 4 | 0 | 6G |
| Compute | 2 | 2 | 1 | 16G |

can be deployed with:

```
./vagrant_startup.sh -G 1 -N 2 -C 2 -x 16384 -M 3 -m 2 -y 2048 -L 1 -l 4 -z 6144
```

> This configuration requires at least 2 GPUs configured for passthrough.

# Enabling Virtualization and GPU Passthrough

On many machines, virtualization and GPU passthrough are not enabled by default. Follow these directions so that a virtual DeepOps cluster can start on your host machine with GPU access on the VMs.

## BIOS and Bootloader Changes

To support KVM, we need GPU pass through. To enable GPU pass through, we need to enable VFIO support in BIOS and Bootloader.

### BIOS Changes

* Enable BIOS settings: Intel VT-d and Intel VT-x
* Enable BIOS support for large-BAR1 GPUs: 'MMIO above 4G' or 'Above 4G encoding', etc.

**DGX-2 SBIOS**
* VT-x:  enable
* VT-d:  enable
* MMIO above 4G: enable
* Intel AMT: disable

**DGX-1/1V SBIOS**
* VT-x: Intel RC Setup -> Processor Configuration -> VMX
* VT-d: Intel RC Setup -> IIO Configuration -> VT-d
* MMIO above 4G: Advanced -> PCI Subsystem Setting -> Above 4G Encoding

**DGX Station SBIOS**
* VT-x: 
* VT-d: 
* MMIO above 4G: verify virtualization support is enabled in the BIOS, by looking for vmx for Intel or svm for AMD processors...

```
$ grep -oE 'svm|vmx' /proc/cpuinfo | uniq
vmx
```

### Bootloader Changes

1. Add components necessary to load VFIO (Virtual Function I/O). VFIO is required to pass full devices through to a virtual machine, so that Ubuntu loads everything it needs. Edit and add the following to `/etc/modules` file:
```
pci_stub
vfio
vfio_iommu_type1
vfio_pci
kvm
kvm_intel
```

2. Next, need Ubuntu to load IOMMU properly. Edit `/etc/default/grub` and modify "GRUB_CMDLINE_LINUX_DEFAULT", by adding "intel_iommu=on" to enable IOMMU. May also need to add "vfio_iommu_type1.allow_unsafe_interrupts=1" if interrupt remapping should be enabled. Post these changes, the GRUB command line should look like this:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on vfio_iommu_type1.allow_unsafe_interrupts=1
iommu=pt"
```

3. Enable the vfio-pci driver on boot:
```
$ echo vfio-pci | sudo tee /etc/modules-load.d/vfio-pci.conf
```

4. Run `sudo update-grub` to update GRUB with the new settings and reboot the system.

### Blacklist the GPU Devices

We do not want the host running DGX Base OS to use the GPU Devices. Instead we want Guest VMs to get full access to the NVIDIA GPU devices. Hence, in the DGX Base OS on the host,  blacklist them by adding their IDs to the initramfs.

1. Run the command `lspci -nn | grep NVIDIA` to get the list of PCI-IDs
```
08:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
0a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
10:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
11:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
12:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
18:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
1a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
89:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
8b:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
92:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
94:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
```

2. Edit `/etc/modprobe.d/vfio.conf` and add this line:
```
options vfio-pci ids=10de:1db1,10de:1ac1
```

NOTE: First entry is for Volta and the latter for NVSwitch

3. Rebuild the initramfs by running `sudo update-initramfs -u` and reboot the system.

4. After the system reboots, verify GPU devices and NVSwitches are claimed by vfio_pci driver by running `dmesg | grep vfio_pci`...
```
[   15.668150] vfio_pci: add [10de:1db1[ffff:ffff]] class 0x000000/00000000
[   15.736099] vfio_pci: add [10de:1ac1[ffff:ffff]] class 0x000000/00000000
```

```
$ lspci -nnk -d 10de:1ac1
10:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
11:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
12:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
```

If the `Kernel driver in use` is not `vfio-pci` and instead the nvidia driver, it may be necessary to blacklist the nvidia driver or instruct it to load vfio-pci beforehand...

```
$ cat /etc/modprobe.d/nvidia.conf
softdep nvidia_384 pre: vfio-pci
```

One more check...

```
$ lspci -nnk -d 10de:1db1
08:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
0a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
18:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
1a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
89:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
8b:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
92:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
94:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
```



