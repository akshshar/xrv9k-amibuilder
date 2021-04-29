#!/bin/bash
#
# October 2014, Neil McGill, Rich Wellum, Alpesh Patel
#
# Copyright (c) 2014-2018 by Cisco Systems, Inc.
# All rights reserved.
#
# HELP
#
# This tool creates and launches a QEMU/KVM virtual machine instance for the
# cisco sunstone platform. At a minimum an ISO is needed to allow the system
# to boot. Additionally for the system to successfully install, a blank hard
# disk is needed. The tool will create any needed disks if not found.
#
# On subsequent runs you will be prompted if you wish to repeat the install
# phase or boot from the existing installed disks.
#
# Simple boot
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso
#
# Or if you have a pre-booted VMDK or OVA
#
#    sunstone.sh -disk ios-xrv9k-mini-x.vmdk
#    sunstone.sh -disk ios-xrv9k-mini-x.ova
#
# Suggested usage:
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso -hw-profile vrr
#       (24 Gb ram, 8 cores)
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso -hw-profile vpe
#       (20 Gb ram, 4 cores)
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso -hw-profile lite
#       (4 Gb ram, 2 core)
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso -hw-profile vpe_performance
#       (24 Gb ram, 8 cores, cpus pinned to first numa core)
#        Guest LXC VM CPU split     : 1/1/0-1,2-7
#        Total guest cores          : 8 (1 x 8 x 1 x 1)
#        Control plane guest cores  : *Guest* CPUS 0 .. 1
#        Data plane guest cores     : *Guest* CPUS 2 .. 7
#        NUMA nodes:
#         Node 0 CPUs 0,2,4,6,8,10,12,14,16,18,20,22 **EXAMPLE**
#         Node 1 CPUs 1,3,5,7,9,11,13,15,17,19,21,23 **EXAMPLE**
#        NUMA 0 chosen CPUs:
#         0,2,4,6,8,10,12,14 **EXAMPLE**
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso -hw-profile vpe_performance -numa 1
#       (24 Gb ram, 8 cores, cpus pinned to numa core 1)
#        Guest LXC VM CPU split     : 1/1/0-1,2-7
#        Total guest cores          : 8 (1 x 8 x 1 x 1)
#        Control plane guest cores  : *Guest* CPUS 0 .. 1
#        Data plane guest cores     : *Guest* CPUS 2 .. 7
#        NUMA nodes:
#         Node 0 CPUs 0,2,4,6,8,10,12,14,16,18,20,22 **EXAMPLE**
#         Node 1 CPUs 1,3,5,7,9,11,13,15,17,19,21,23 **EXAMPLE**
#        NUMA 1 chosen CPUs:
#         1,3,5,7,9,11,13,15 **EXAMPLE**
#
# Terminal output
# ---------------
#
# The sunstone platform supports serial port access only. As such we need a
# way to connect to the telnet ports that we randomly allocate at startup for
# sunstone to use. For ease of use, this tool can launch a variety of terminals
# and then within those terminals will telnet to the sunstone serial ports.
#
# A variety of terminal types is supported e.g.:
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --gnome
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --mrxvt
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --konsole
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --xterm
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --screen
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --tmux
#
# The tool by default will try to find one of the above if no option is
# specified.
#
#   --gnome can sometimes cause issues if you are not running a gnome desktop
#
#   --screen is a text only interface. Generally you need a .screenrc and should
#   be familiar with how to use screen before attempting to use this one!
#
#   --tmux is also a text-only interface, intended to be a modern alternative to
#   screen.
#
# Output to these terminals is logged into the work dir that is created when
# you launch the VM. In this way you have a record of every session.
#
#
# Networking
# -----------
#
# The tool also creates a number of network interfaces to connect the VM to.
# These interfaces are named 'Lx...' or 'Xr...' tap with a prefix to make the
# names unique. Key:
#
#    {PREFIX}Lx1 - MgmtEth0/RP0/CPU0/0, eth0, connected to {PREFIX}LxBr1
#ifdef CISCO
#    {PREFIX}Lx2 - eth1 / control eth, connected to {PREFIX}LxBr2
#    {PREFIX}Lx3 - eth2 / host access, connected to {PREFIX}LxBr3
#endif
#ifdef PROD
#    {PREFIX}Lx2 - eth1 / unused, connected to {PREFIX}LxBr2
#    {PREFIX}Lx3 - eth2 / unused, connected to {PREFIX}LxBr3
#endif
#    {PREFIX}Xr1 - GigabitEthernet0/0/0/0 connected to {PREFIX}XrBr1
#    {PREFIX}Xr2 - GigabitEthernet0/0/0/1 connected to {PREFIX}XrBr2
#    {PREFIX}Xr3 - GigabitEthernet0/0/0/2 connected to {PREFIX}XrBr3
#
#    'Lx' here indicates an interface that is being used fo
#    network (virbr0) and can hence be used for ssh access to the VM.
#
#    'p' indicates a private interface attached to its own bridge which may
#    then be used to connect to other VMs that also connect to the same named
#    bridge.
#
# If you wish to run multiple instances at the same time, you must use the
# -net option to provide some other name other than your login name. e.g.
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --gnome -net mynet2
#
#ifdef CISCO
# Topology builder
# ----------------
#
#  1) Build any topo;
#
#  2) create topo diagram - with the exact/actual interfaces (and PCI IDs)
#  that will be created on the routers;
#
#  3) sim-config.xml (VXR2) - ready to launch sim;
#
#  4) topo file and commands used to launch sunstone via sunstone.sh.
#
#  http://ott-pxe1/cgi-bin/sunstone.cgi
#
#  Note: this is light weight, and is complimentary to VM-maestro
#endif
#
# Disks
# -----
#
# By default the tool will create raw disks. These can be very large. To save
# space you can use the qcow2 option to enable copy on write functionality.
# This may have a performance hit but will drastically reduce disk space
# needed.
#
#
# Background running
# ------------------
#
# This tool can run qemu in the background. The telnet ports are logged into
# the work dir created. You may then manually telnet to the router.
#
#
#ifdef CISCO
# Development mode
# ----------------
#
# Development mode will cause the ISO to be expanded and the __development=true
# option to be added to the command line. This will cause the system to not
# allow IOS XR to launch on the console port. Instead login to the host will
# be provided.
#
# One caveat, as you will now be double telnetted, it is necessary to be able
# to telnet from the host into the guest and then exit back to the host
# without killing both telnet connections. For this purpose, you can do:
#
#   For XR:
#        telnet -e ^Q localhost 9001
#
#   For calvados:
#        telnet -e ^Q localhost 50000
#
# And to escape out to the host telnet session, hit "ctrl ]" and then "q enter"
#
#endif
#
# VM access
# ---------
#
# Once in the host VM you can ssh to the containers manually via:
#
#   For XR:
#     ssh -l root 10.11.12.14
#
#   For calvados:
#     ssh -l root 10.11.12.15
#
#   For UVF:
#     ssh -l root 10.11.12.115
#
# And then back to the host via
#
#     ssh -l root 10.0.2.16
#
#
# sshfs access
# ------------
#
# To mount a directory remotely you may follow this approach (which will need
# tweaking for your own nameservers):
#
#     1. on host VM, get the address QEMU allocated for us on virbr0:
#
#         [host:~]$ ifconfig eth0
#         eth0      Link encap:Ethernet  HWaddr 52:46:01:5B:D1:78
#                 inet addr:192.168.122.122  Bcast:192.168.122.255  Mask:255.255.255.0
#
#     2. on host, ssh into sunstone VM
#
#         ssh -l root 192.168.122.122
#
#     3. on sunstone VM, set up /etc/resolv.conf
#
#         cat >/etc/resolv.conf <<%%
#ifdef CISCO
#     nameserver 64.102.6.247
#     nameserver 171.70.168.183
#     nameserver 173.36.131.10
#     nameserver 173.37.87.157
#     search cisco.com
#endif
#ifdef PROD
#     nameserver a.b.c.d
#     search my domain
#endif
#     %%
#
#     4. on sunstone VM, create any mount points you need e.g. I am mounting
#        /ws/nmcgill-sjc
#
#         mkdir -p /ws/nmcgill-sjc
#         sshfs -o idmap=user -o allow_other nmcgill@sjc-ads-2617:/ws/nmcgill-sjc /ws/nmcgill-sjc
#
#     5. To do the same in the calvados VM
#
#         ssh 10.11.12.15
#         mkdir -p /ws/nmcgill-sjc
#         sshfs 10.0.2.16:/ws/nmcgill-sjc /ws/nmcgill-sjc
#
#     6. To do the same in the XR VM
#
#         ssh 10.11.12.14
#         mkdir -p /ws/nmcgill-sjc
#         sshfs 10.0.2.16:/ws/nmcgill-sjc /ws/nmcgill-sjc
#
#
# Creating OVA, VMDK, RAW and QCOW2 images
# ----------------------------------------
#
# To create a VMDK, first we must boot the ISO and allow the system to install
# onto the disk. When the system then reboots we are able to create an OVA
# from that disk image. The OVA contains the VMDK which can be extracted
# then be used as an deployable virtual machine object within vSphere,
# OpenStack, VirtualBox etc.... e.g.:
#
#    sunstone.sh -iso ios-xrv9k-mini-x.iso --export-images
#
# Which you can then boot via:
#
#    sunstone.sh -disk ios-xrv9k-mini-x.vmdk
#
#
# Usage
# -----
#
# Usage: ./sunstone.sh -image <sunstone iso>
#
#   -i
#   --iso <imagename>   : Name of ISO to boot from.
#
#                         Note, if using NFS, QEMU can be blocked from reading
#                         the disk image (by SELinux) if this is on NFS. You can
#                         try this workaround:
#
#             1. Check the status of the virt_use_nfs boolean in SELinux.
#             getsebool virt_use_nfs
#
#             2. Temporarily turn on the boolean.
#             setsebool virt_use_nfs on
#
#             3. Check the status of the virt_use_nfs boolean in SELinux.
#             getsebool virt_use_nfs
#
#             4. If you want to make the change persistant, then add the -P
#             option to setsebool.
#             setsebool -P virt_use_nfs on
#
#   --disk <name>       : Name of a preinstalled disk to boot from.
#
#   --disk-size <x>[G]  : Disk size in GB
#
#   --disk2 <name>      : Name of a non bootable disk to add
#
#   --serial_number <serial_number> : Serial number of the XRv9K VM in its BIOS
#
#   --kernel <name>     : Kernel to boot with
#
#   -n
#   -net
#   --name <netname>    : Name of the network. Defaults to $LOGNAME
#
#   --node <netname>    : Name of an individual router node on the network.
#                         For example running three routers on the same
#                         network.
#
#                           sunstone.sh -node node1
#                           sunstone.sh -node node2
#                           sunstone.sh -node node3
#
#                         In this case no net name is used so we use the userid
#                         to create the bridge. You can do this though:
#
#                           sunstone.sh -net 1 -node node1
#                           sunstone.sh -net 1 -node node2
#                           sunstone.sh -net 1 -node node3
#
#                           sunstone.sh -net 2 -node node1
#                           sunstone.sh -net 2 -node node2
#                           sunstone.sh -net 2 -node node3
#
#                         To launch the same set of nodes twice in different
#                         unconnected networks.
#
#                         See -topo for more information on the use of this
#                         option.
#   -w
#   --workdir <dir>     : Place to store log and temporary files.
#                         Default is to use the current working directory.
#
#   --clean             : Clean only. Attempt to clean up taps from previous run
#                         Will attempt to kill the old QEMU instance also.
#
#   --term-bg <color>   : Terminal background color (xterm, mrxvt)
#
#   --term-fg <color>   : Terminal foreground color (xterm, mrxvt)
#
#   --term-font <font>  : Terminal font (xterm, mrxvt)
#
#           e.g. -term-font '-*-lucidatypewriter-*-*-*-*-10-*-*-*-*-*-*-*'
#
#   --term-profile <p>  : Terminal foreground color (gnome, konsole)
#
#                         e.g.  -term-profile my-profile
#
#   --term-opt <opts>   : Options to passthrough to the terminal windoe.
#
#                         e.g.  -term-opt '-title \"hello there\"'
#
#   --gnome             : Use tabbed gnome terminal
#
#   --xterm             : Use multiple xterms
#
#   --konsole           : Open tabbed konsole sessions.
#
#   --mrxvt             : Open tabbed mrxvt sessions. If you want to tweak the
#                         appearance, you should edit your  ~/.mrxvtrc e.g.
#
#                           Mrxvt.xft:              1
#                           Mrxvt.xftAntialias:     1
#                           Mrxvt.xftFont:          DejaVu Sans Mono
#                           Mrxvt.xftSize:          17
#
#   --screen            : Open screen sessions for telnet.
#
#   --tmux              : Open tmux session.
#
#   --noterm            : Launch no terminals. Anticipation is that you will
#                         manually telnet to the ports.
#   --log               : Spawn telnet sessions to serial ports. Assumes no
#                         xterms are needed.
#   -f
#   --force             : Just do it, take defaults.
#
#   -r
#   --recreate          : Recreate disks.
#
#ifdef CISCO
#   --dev               : Run in sunstone development mode (default).
#
#   --docker            : Enable specific feature for running sunstone on Docker
#                         such as external file system.
#
#endif
#
#   --hw-profile <profile>
#
#                       : Configure a hw profile type to modify the internal
#                         memory and CPU requirements of the virtual router.
#
#                         Supported profiles:
#
#                              "vpe" (virtual provider edge) - Default
#                                       OPT_PLATFORM_MEMORY_MB=20480
#                                       OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"
#                              "vpe_performance" (virtual provider edge)
#                                       OPT_PLATFORM_MEMORY_MB=24576
#                                       OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
#                                       OPT_ENABLE_HW_PROFILE_CPU="1/1/0-1,2-7"
#                              "vpe_perf_red_hat" (virtual provider edge)
#                                       OPT_PLATFORM_MEMORY_MB=24576
#                                       OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
#                                       OPT_ENABLE_HW_PROFILE_CPU="1/1/0-1,2-7"
#                              "vrr" (virtual route reflector)
#                                       OPT_PLATFORM_MEMORY_MB=24576
#                                       OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
#                              "lite" (virtual provider edge lite)
#                                       OPT_PLATFORM_MEMORY_MB=4096
#                                       OPT_PLATFORM_SMP="-smp cores=1,threads=1,sockets=1"
#
#                         If a file <profile> also exists, it will be sourced
#                         into the script to allow overriding of defaults. e.g.
#
#                         vrr.profile:
#
#                         OPT_PLATFORM_MEMORY_MB=32768
#                         OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"
#
#                         The following are the default allocations that will
#                         be made based on the profile name and the amount of
#                         CPU and memory given. The default profile is vpe:
#
#                         CPU allocation for the system. refer to The PLATFORM_CPU_PROFILES
#                         table at calvados/sunstone_pkg/hw_profiles/platform_hw_profiles.sh
#
#   --hw-profile-vm-mem-gb <a>/<b>/<c> e.g. 1/16/4
#
#                       : Sets the amount of RAM in Gb given to each domain.
#
#                         IOS XRv 9000 depending on if it is routing heavy may
#                         need 4 vCPU and 20 Gig or RAM for full BGP routing
#                         tables.
#
#                         The following domains are configured in order within
#                         this value:
#
#                           <a> - Calvados, IOS XR management plane
#                           <b> - IOS XRv routing plane
#                           <c> - Data plane (which needs core assignment)
#
#   --hw-profile-packet-mem-mb <a>/<b>/<c> e.g. 1/16/4
#
#                       : Sets the amount of packet RAM in Mb given to each
#                         domain. Currently only XR uses this field so you
#                         can give either "-/value/-" or just "value".
#
#                         By default the amount of packet memory is scaled
#                         according to the VM memory.
#
#                         The following domains are configured in order within
#                         this value:
#
#                           <a> - Calvados, IOS XR management plane
#                           <b> - IOS XRv routing plane
#                           <c> - Data plane (which needs core assignment)
#
#   --hw-profile-cpu <a>/<b>/<cp-cp>,<dp-dp>
#
#                       : Controls the vCPU allocation for the system. The
#                         fields can be understood as follows:
#
#                           <a> - Calvados, vCPU allocation
#                           <b> - IOS XRv vCPU allocation
#                           <cp-cp> - Range of vCPU cores for Calvados and XR
#                                     to share
#                           <dp-dp> - Range of vCPU cores dedicated to the
#                                     dataplane.
#
#                         For example for a host with 5 vCPUS and the
#                         --hw-profile-cpu value of 1/1/0-1,2 the fields can
#                         be understood as:
#
#                   vrr           vpe       lite
#                   1/1/0-1,2-4   .......  ......
#                   ^ ^  ^   ^    ^        ^
#                   | |  |   |    |        |
#                   | |  |   |    |        if using lite profile
#                   | |  |   |    If using vpe profile, use these values.
#                   | |  |   |
#                   | |  |   |
#                   | |  |   Dataplane is on cores 2-4 for vrr profile.
#                   | |  |
#                   | |  |
#                   | |  Cavlados and XR are on cores 0-1 for vrr profile.
#                   | |
#                   | |
#                   | IOS XRv gets 1vCPU for vrr profile.
#                   |
#                   |
#                   Calvados gets 1 vCPU for vrr profile
#
#   --rx-queues-per-port <n>
#
#                       : Configures the specified number of rx queues on each
#                         dataplane interface. RSS (Receive Side Scaling)
#                         support by each NIC is required.
#
#   --vga               : Enable tweaks useful for operating in the cloud
#                         e.g. VGA console instead of serial port
#
#   --vnc <host>        : Start a VNC server. This is the default for cloud
#                         mode.
#
#                         e.g. -vnc 127.0.0.1:0
#                              -vnc :0
#ifdef CISCO
#   --sim               : Run in sunstone simulation mode (deprecated).
#
#   --prod              : Run in sunstone production mode.
#
#endif
#   --xrvr              : Tweak behaviour for booting legacy IOS XRv 32 bit
#
#   --ucs               : Tweak behaviour for booting an IOS UCS image
#
#ifdef CISCO
#   --n9kv              : Tweak behaviour for booting a Nexus 9kV image
#
#endif
#   --iosv
#   --vios              : Tweak behaviour for booting an vIOS image
#
#   --linux             : This is a vanilla linux VM. Avoid patching grub for
#                         cisco specifics.
#
#   --disable-logging   : Do not record any telnet session output
#
#   --disable-log-symlinks
#                       :
#                         Don't create symlinks to logging files. Useful in
#                         large topologies where we end up with a ton of logs.
#
#   --enable-extra-tty  : Extra 3rd and 4th TTY (default)
#
#   --disable-extra-tty : Disable 3rd and 4th TTY.
#
#   --disable-kvm       : Disable KVM acceleration support
#
#   --disable-sudo      : Try to operate without any use of sudo
#
#   --disable-daemonize : Disable daemonizing of KVM
#
#   --disable-monitor   : Do not launch the QEMU monitor
#
#   --disable-smp       : Disable SMP
#
#   --disable-numa      : Disable NUMA Balancing (useful for compilation on ADS)
#
#   --disable-ksm       : turn kernel same page merging (ksm) off on host
#
#   --smp               : Orverride base SMP options e.g.
#                           -smp cores=4,threads=1,sockets=1
#   -m
#   --memory <x>[MG]    : Memory in GB, 20G default. e.g. --mem 20G
#
#   --install-memory x[MG]
#                       : Memory to allocate to QEMU for the initial install
#                         process, independent of memory to be allocated to
#                         any exported OVF/OVA.
#
#   --bios <file>       : BIOS to boot with
#
#   --82599
#   --10g               : Scan all intel 82599 NICs on the host and add them
#                         to the QEMU command line.
#
#                         You may need to do the followin on your system:
#
#                         Create /etc/modprobe.d/ixgbe.conf, and add the following line:
#                         (needed to support 10G interfaces)
#
#                            options ixgbe allow_unsupported_sfp=1
#
#                         then;
#
#                            $ modprobe ixgbe
#                            $ rmmod ixgbe
#
#                         Note: -pci is mutually exclusive.
#
#   --bcm577            : Scan for all broadcom 577 NICs on the host and add
#                         them to the QEMU command line.
#
#                         Note: -pci is mutually exclusive.
#
#   --disable-network   : Do not create any network interfaces
#
#   --disable-address-assign
#                       : Do not allocate any IP addresses for bridges
#
#   --enable-snooping
#                       : Enable multicast snooping for bridges
#
#   --disable-snooping
#                       : Disable multicast snooping for bridges
#
#   --enable-querier
#                       : Enable multicast querier for bridges
#
#   --disable-querier
#                       : Disable multicast querier for bridges
#
#   --enable-lldp
#                       : Enable lldp packets to pass through bridges
#
#   --enable-serial-virtio  : Enable faster virtio based access for serial ports.
#   --disable-serial-virtio : Disable faster virtio based access for serial ports.
#                             Default is to use non virtio for now.
#
#   --enable-disk-virtio  : Use faster virtio based access for disks.
#   --disable-disk-virtio : Use slower IDE based access for disks.
#                           Default is to use virtio.
#
#   --disable-disk-bootstrap-virtio
#                       : As above but do not use virtio for bootstrap disks only
#
#   --disable-runas     : Disable KVM -runas option (if initgroup causes issues)
#
#   --runas <x>         : Run as user <x>
#
#   --disable-boot      : Exit after baking ISOs. Do NOT boot QEMU.
#
#   --disable-modify-iso
#                       : Prevent the script from adding a UUID or enabling
#                         other boot time flags on the given ISO.
#
#   --generate-xml-only : Exit after generating XML
#
#   --disable-taps      : Do not create TAP interfaces. Instead disconnected
#                         interfaces will be created. Useful for booting for
#                         a basic test if networking tools (tunctl) are not
#                         installed.
#   --disable-bridges   : Do not create bridge interfaces.
#
#ifdef CISCO
#   --enable-fabric-nic : (XRv64 only) Reserve a NIC for fabric between VMs.
#
#endif
#   --data-nics <x>     : Number of data taps to initialize (i.e. used by XR)
#   --host-nics <x>     : Number of host taps to initialize (i.e. used by guest
#                         VM for host access)
#
#   --data-nic-type <x> : Use e1000, virtio, vmxnet3 or vhost-net on data interfaces
#   --host-nic-type <x> : Use e1000, virtio, vmxnet3 or vhost-net on host interfaces
#
#   --data-nic-queues <x> : For vhost and virtio only, how many flows to support
#   --host-nic-queues <x> : For vhost and virtio only, how many flows to support
#
#   --data-nic-csum-offload-disable
#   --host-nic-csum-offload-disable
#   --data-nic-csum-offload-enable
#   --host-nic-csum-offload-enable
#
#                       : Checksum offloading is a feature of the NIC where it
#                         can do the checksumming instead of the OS and so leads
#                         to higher performance. For XR this causes checksum
#                         errors for TCP traffic and may need to be disabled.
#
#   --mtu <x>           : MTU for dataplane interfaces
#
#   --txqueuelen <x>    : Tx queue length for dataplane interfaces
#
#   -p
#   --pci ...           : Assign a specific PCI passthrough device to QEMU
#                            -pci 05:00.0
#                         or
#                            -pci 0000:05:00.0
#                         or
#                            -pci eth2
#
#                         Note: -10g and -pci are mutually exclusive.
#
#                         See this link for more info:
#
#                           http://www.linux-kvm.org/page/How_to_assign_devices_with_VT-d_in_KVM
#
#                         To attach the device to a guest numa node, specify the number of
#                         numa nodes with -numa-pxb and then the node number after the device.
#                            -numa-pxb 2        # 2 numa nodes
#                            -pci 05:00.0 1     # interface attached to node 1
#
#   --vfiopci ...      : Assign a specific PCI passthrough device to QEMU
#                            -vfiopci 05:00.0
#                         or
#                            -vfiopci 0000:05:00.0
#
#                         Note: -10g and -vfiopci are mutually exclusive.
#
#                         See this link for more info:
#
#                           http://www.linux-kvm.org/page/How_to_assign_devices_with_VT-d_in_KVM
#
#   --numa-pxb <n>      : Create <n> pci bridges for <n> guest numa nodes (see --pci above)
#   --pxb <n>           : Create <n> pci bridges on numa node 0
#
#   --virtspeed <n>     : Define interface naming for virtual interfaces. The default is
#                         GigabitEthernet. --virtspeed 100 changes it to HundredGigE.
#
#   --numa-memdev <lst> : Create hugepages in each guest numa node. The parameter is a list
#                         of sizes in GB. The first size is for numa node 0, the second is
#                         for numa node 1, etc
#
#   --passthrough ...   : Extra arguments to pass to QEMU unmodified.
#
#   --huge              : Check huge pages are enabled appropriately
#
#   --guest-hugepages   : Number of 2MB hugepages to allocate within the
#                         Sunstone VM.
#                         Default is 3072. Value must be a multiple of 1024
#
#   --cpu-pin a,b,c     : Comma seperated list of CPUs to pin to e.g. 1,2,3,4
#
#   --numa-pin <n>
#   --numa-pin <n-n>    : Selected CPUs must from the given numa node <n> or
#                         node range <n-n>
#
#   --cmdline-append .. : Extra arguments to pass to the Linux cmdline
#ifdef CISCO
#                         e.g. -cmdline-append "__development=true"
#endif
#
#                         ** IOS XRv 9000 only. Not used with XRVR or Linux
#                            images **
#
#   --cmdline-remove .. : Extra arguments to pass to the Linux cmdline
#                         e.g. -cmdline-remove "quiet"
#
#                         ** IOS XRv 9000 only. Not used with XRVR or Linux
#                            images **
#
#   --distributed       : Adds the cmdline arg __distributed=true
#   --boardtype <x>     : Mods the cmdline arg boardtype=x (RP, LC only)
#   --rack <x>          : Adds the cmdline arg __rack=x
#   --slot <x>          : Adds the cmdline arg __slot=x
#   --qcow2             : Create QCOW2 disks during ISO install.
#
#   --export-images [output directory]
#                       : Once installed, create OVA, VMDK, RAW and QCOW2 images
#                         from the disk image using default OVF template.
#
#   --ovf <name>        : OVF template to use for OVA generation.
#
#   --bootstrap-config
#   -b
#   --b <file name>     : Include a bootstrap CLI file (non admin)
#
#   --topology
#   --topo <name>       : Source a topology file. sunstone.topo will be
#                         looked for as a default.
#
#                         This topology file then allows you to override
#                         the bridge names that are used by default.
#
#                         Examples:
#
#                   b2b.topo:
#                              +---------+    +---------+
#                              |  node1  |    |  node2  |
#                              +---------+    +---------+
#                                1  2  3        1  2  3
#                                |  |  |        |  |  |
#                                +-----|-[br1]--+  |  |
#                                   |  |           |  |
#                                   +--|-[br2]-----+  |
#                                      |              |
#                                      +-[br3]--------+
#
#ifdef CISCO
#                   b2b-ha.topo
#
#                      +------------------+      +-----------------+
#                      |      node1       |      |      node2      |
#                      |                  |      |                 |
#                      | HostNICs DataNICs|      |HostNICs DataNICs|
#                      +------------------+      +-----------------+
#                        1  2  3  1  2  3         1  2  3  1  2  3
#                           |     |  |  |            |     |  |  |
#                           +--------------[Fab]-----+     |  |  |
#                                 |  |  |                  |  |  |
#                                 +-----|--[br1]-----------+  |  |
#                                    |  |                     |  |
#                                    +--|--[br2]--------------+  |
#                                       |                        |
#                                       +--[br3]-----------------+
#
#endif
#                   chain.topo:
#
#                              +---------+    +---------+   +---------+
#                              |  node1  |    |  node2  |   |  node3  |
#                              +---------+    +---------+   +---------+
#                                1  2  3        1  2  3       1  2  3
#                                |              |  |          |
#                                +------[br1]---+  +---[br2]--+
#
#                   longchain.topo:
#
#                          +---------+    +---------+   +---------+  +---------+
#                          |  node1  |    |  node2  |   |  node3  |  |  node4  |
#                          +---------+    +---------+   +---------+  +---------+
#                            1  2  3        1  2  3       1  2  3      1  2  3
#                            |              |  |             |  |            |
#                            +------[br1]---+  +---[br2]-----+  +---[br3]----+
#
#                   5star:
#                                             +---------+
#                                             |  node2  |
#                                             +---------+
#                                                  1
#                                                  |
#                                                 br2
#                                                  |
#                                                  3
#                              +---------+    +---------+   +---------+
#                              |  node1  |    | node5   |   |  node4  |
#                              +---------+    +---------+   +---------+
#                                   1           1  2  4          1
#                                    \          /  |  \         /
#                                     -br1------   |   --br4----
#                                                 br3
#                                                  |
#                                                  1
#                                             +---------+
#                                             |  node3  |
#                                             +---------+
#
#                   4star:
#                                             +---------+
#                                             |  node2  |
#                                             +---------+
#                                               1  2  3
#                                              /   |   \
#                                  ----br1----     |    -br2-
#                                 /                |         \
#                                1  2  3           |          1  2  3
#                              +---------+         |        +---------+
#                              |  node1  |        br5       |  node4  |
#                              +---------+         |        +---------+
#                                1  2  3           |          1  2  3
#                                    \             |            /
#                                     -br3-----    |    -br4----
#                                              \   |   /
#                                               1  2  3
#                                             +---------+
#                                             |  node3  |
#                                             +---------+
#
#                          ####################################################
#
#                         And to launch 4star you would then boot 4 instances
#                         like:
#
#                           sunstone.sh -node node1 -topo b2b.topo
#                           sunstone.sh -node node2 -topo b2b.topo
#                           sunstone.sh -node node3 -topo b2b.topo
#                           sunstone.sh -node node4 -topo b2b.topo
#
#                         Note that the managmement interface is not
#                         connected to virbr0.
#
#                         If this is required the following could be used
#
#                         mgmt.topo:
#
#                          case $OPT_NET_AND_NODE_NAME in
#                          *)
#                              BRIDGE_HOST_ETH[1]=virbr0
#                              ;;
#                          esac
#
#                         and then chain this onto the end of an existing
#                         topo e.g.:
#
#                           sunstone.sh -node node3 -topo b2b.topo -topo mgmt.topo
#
#   --host <ip/host>    : Use this host address for telnet connectivity. Defaults
#                         to localhost.
#
#   --port <number>     : Use this port for serial access. The default is to
#                         randomly allocate port numbers. With this option you
#                         can give fixed port numnbers. If you specify this
#                         option multiple times (up to 4) the port number will
#                         be used for successive serial ports.
#
#   --bg                : Run in the background. Do not open any consoles.
#
#   --kvm               : Do not try and find a working kvm/qemu executable.
#                         Use the one given.
#
#   --tmpdir            : Set TMPDIR (used for qemu snapshots)
#
#   --snapshot          : Enable KVM snapshot feature. Snapshot files will
#                         live in TMPDIR
#
#   --qemu-img          : Do not try and find a working qemu-img executable.
#                         Use the one given.
#
#   --no-reboot         : Exit the script on qemu shutdown
#
#   --delay <x>         : Sleep for a period of x seconds before launching
#
#   --boot-virsh        : Launch sunstone using the generated virsh XML
#
#   --debug             : Debug logs
#
#   --verbose           : Verbose logging, include program name in each line.
#                         Useful when being called from another script.
#
#   --tech-support      : Gather tech support info and then exit
#
#   --mlock             : Lock qemu and guest pages in memory to avoid memory
#                         reclaim
#
#   --sr-iov            : Do the modprobes and checks appropriate for SR-IOV,
#                         using the sysfs method for configuration
#                         must use the pfif and vfnum options as well
#                         only use on the first instance of sunstone.sh
#   --sr-iov-dep <vfs>  : Do the modprobes and checks appropriate for SR-IOV,
#                         using the deprecated parameter passing method
#                         must use the pfif option as well
#                         only use on the first instance of sunstone.sh
#   --sr-iov-bdw <ctx>  : Bandwidth context of sriov, either x, 40 or 1
#                         default is x for 10G
#   --pfif <ifname>     : Do the ifconfigs and checks appropriate for SR-IOV,
#                         must use with the sr-iov option as well
#                         only use on the first instance of sunstone.sh
#   --vfnum <num>       : Do the sysfs and checks appropriate for SR-IOV,
#                         must use with the sr-iov option as well
#                         only use on the first instance of sunstone.sh
#
#
#                         for example on a UCS with a 2 X 10G card in slot 3:
#
# sysfs method
#./sunstone/sunstone.sh -i xrv9k-full-x.iso -f --node node1 --sr-iov --pfif p1p1 --vfnum 2 --pfif p1p2 --vfnum 4 -pci 03:10.0 -pci 03:10.1 -pci 03:10.3 -dev -hw-profile vpe_performance
#./sunstone/sunstone.sh -i xrv9k-mini-x.iso -f --node node2 -pci 03:10.2 -pci 03:10.5 -pci 03:10.7 -dev -cpu-pin 8,9,10,11,12,13,14,15 -smp cores=8,threads=1,sockets=1 -hw-profile-cpu 1/1/0-1,2-7
#
# deprecated method:
#./sunstone/sunstone.sh -i xrv9k-mini-x.iso -f --node node1 --sr-iov 2,4 --pfif p1p1 --pfif p1p2 -pci 03:10.0 -pci 03:10.1 -pci 03:10.3 -dev -hw-profile vpe_performance
#./sunstone/sunstone.sh -i xrv9k-mini-x.iso -f --node node2 -pci 03:10.2 -pci 03:10.5 -pci 03:10.7 -dev -cpu-pin 8,9,10,11,12,13,14,15 -smp cores=8,threads=1,sockets=1 -hw-profile-cpu 1/1/0-1,2-7
#
#   --vfix		: to setup a virtual function index for following
#                         options like VF vlan and VF rate limit setup
#   
#   --vfvl              : to set a vlan administratively to simulate some
#                         hypervisor environments like ESXi or AWS
#
#   --vfrl              : to set a rate limit on a virtual function at init
#                         unit is mega bits per seconds you can also do
#                         it after init...
#
#                         to change the rate limit of one virtual function, use
#                         the following (1Gbps in this case):
#
#                         ip link set p1p1 vf 0 rate 1000
#
#   --loglevel <num>    : Kernel log to console level. See:
#
#                         https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/tree/Documentation/sysctl/kernel.txt
#
#                         and use 0 for all logs.
#
#ifdef CISCO
#   --guess_iso <type> <release> :
#                           Instead of providing sunstone.sh with an ISO
#                           (using -i) - search for an ISO using the <type> and
#                           <release> as a clue.
#                           Currently supporting <types> xrv64 and xrv9k and
#                           <releases> 6.1.1 and latest - where latest is the
#                           current xr-dev C build.
#                         --iso is not needed
#     type = 'XRv64' | 'XRv9k' - case insensitive
#     release = 'latest' | '6.1.1'
#endif
#
#ifdef CISCO
#   --strip             : Strip cisco specific ifdefs
#
#endif
#   -h
#   --help              : This help
#
# END_OF_HELP

help()
{
    cat $0 | sed '/^# HELP/,/^# END_OF_HELP/!d' | grep -v HELP | grep -v ifdef | grep -v endif | sed -e 's/^..//g' | sed 's/^#/ /g'
}

PROGRAM="sunstone.sh"
LAST_OPTION=$0

# 010515 nam 0.9.13 minor change to remove dup port output
#            changed date format to align with linux format in system logs
# 010715 nam 0.9.14 added packet memory config support
# 010815 nam 0.9.15 fixed some bugs in xml generation - full path names for
#                   files and removed sudo from exec
# 011815 nam 0.9.17 added -xr-ap
# 012015 nam 0.9.17 added uuid generation
# 011915 nam merged jimeings changes for snapshot
# 012015 nam 0.9.20 added ucs booting support
# 012015 nam 0.9.21 removed nested lock; ucs with host tty now; boot from existing qcow2 support added
# 013015 nam 0.9.22 added -disk-size option
# 020415 nam 0.9.23 added vios support
# 020515 nam 0.9.25 added virtio for vios
#                 -10g conflicts with -pci warning
#                 allows user to specify kvm/qemu img path
#                 added kvm.real for virl
#                 -export-images was broken in build, expected a path always
# 020915 nam 0.9.26 added ip taptun support for centos
#                 package install should not look for a binary
#                 only check for virbr0 if it is needed in topology
#                 check for telnet in install
# 020915 nam 0.9.27 reordered platform checks to be before main options
#                 fixed disable kvm option
#                 added disable daeominize option
#                 added qemu logging for qemu hacking support
# 020915 nam 0.9.28 check util-linux for uuidgen
# 021115 nam 0.9.30 more robust locking
#                 docker fix to not use virbr0 for eth2
#                 docker fix to not try to install uuidgen if can get uuid
# 021115 nam 0.9.31 ip tuntap support was broken by reordering in 0.9.27
# 021215 asp 0.9.32 increased disk size to accomodate uvf core and log disk (have 2GB extra space)
#                 reclaimed 3GB from UVF, added 5GB, gave 6GB to core/log disk, leaving 2GB spare
# 021615 nam 0.9.33 added docker build support
# 021815 nam 0.9.34 added virtio support for data interfaces
# 021815 nam 0.9.34 added -disable-monitor to help catch qemu crashes
# 021815 nam 0.9.37 bug in -hw-profile-cpu not bounds checking correctly
# 021815 nam 0.9.38 added more -hw-profile-cpu checks
# 021815 nam 0.9.39 Updated to fix a run issue
# 022515 nam 0.9.40 Added -tmpdir option to fix snapshots, fixed -disable-monitor option
# 022515 nam 0.9.41 CR comments, changed to use bash for generated files
# 022615 nam 0.9.42 Enabling sudo all the time unintentionally
# 022615 nam 0.9.43 Add -cpu host for sunstone
# 022615 nam 0.9.44 Made TMPDIR only usable with -tmpdir to avoid issues
#                   Wrap qemu invoke in bask to allow numactl and TMPDIR
#                   to be prefixed safely in a background process
#                   Made tech support run in the background to speed exit
#                   virsh doesn't like the cpu host option
# 030315 asp 0.9.45 Add the -guest-hugepages <value> option to configure what
#                   number of 2MB hugepages to allocate on the guest. Default being
#                   3072.
# 030315 rkw 0.9.46 reflect vpe and vrr profiles in the OVA generation
# 030415 asp 0.9.47 check that the guest-hugepages is a number
# 030515 nam 0.9.48 do not collect tech support unless in error
# 030515 nam 0.9.49 not using enough cores; change to warning
# 030515 nam 0.9.50 added vpe_performance profile
#                   added cpu pinning if numa set and no cpu list
#                   and check for hyper threading
#                   add greater sanity checking of cpu ranges
#                   fix bootstrap config to strip "end"
# 030515 nam 0.9.51 -export-images was now listing images in workdir nor moving them to output dir
# 030615 nam 0.9.52 OVA suffix was broken
# 030615 nam 0.9.53 added sudo retry for mkdir /mnt/huge
# 030615 rkw 0.9.54 generate working virsh xml
# 030615 nam 0.9.55 bootstrap cfg cli broken
# 030615 nam 0.9.56 -export-images broken
# 030615 nam 0.9.57 Not setting tasksetting with correct bitshift
# 030815 rkw 0.9.58 Minor profile fixups to warn, log and label correctly
# 030815 nam 0.9.59 qemu_generate_cmd is used by sanity, aded back
# 030915 nam 0.9.60 ^C interrupt handling on ubuntu 14.10 fixed
# 031115 nam 0.9.61 add BCM577 10G nic support
# 031115 nam 0.9.62 bug in ubuntu lscpu gives huge numbers for node, use socket instead
# 031115 nam 0.9.63 switch to numactl --hardware that seems to give better results
# 031215 rkw 0.9.64 Virsh and OVF fixups
# 031215 d.f 0.9.65 change virsh for bootstrap to pick up workdir image not export dir.
# 031215 asp 0.9.66 fix the check for HT enabled
# 031315 asp 0.9.67 moved copyright to top of script
# 031315 nam 0.9.68 -strip option not handling else. Using PROD to indicate production code
# 031315 rkw 0.9.69 fixed bootstrap CLI ISO to correctly be named
# 031315 nam 0.9.70 changed naming to "Cisco IOS XRV 9000"
# 031615 nam 0.9.70 cot/vmcloud does not support ios-xrv-9000 yet, use ios-xrv
# 031616 nam 0.9.71 added -disk2 option. Huge page calc using Kb and not Mb
# 031617 nam 0.9.72 remove BCM577 option - not supported in mucode
# 031617 nam 0.9.73 fix merge error - also make pci numa -1 a warn not error
# 031615 nam 0.9.71 cot/vmcloud does not support ios-xrv-9000 yet, use ios-xrv
# 031616 nam 0.9.72 added -disk2 option. Huge page calc using Kb and not Mb
# 031617 nam 0.9.73 remove BCM577 option - not supported in mucode
# 031617 nam 0.9.74 fix merge error - also make pci numa -1 a warn not error
# 031815 rkw 0.9.75 ability to export image when no kvm acceleration present on server
# 031618 nam 0.9.76 remove end from bootstrap cfg if found embedded in cfg
#                   added -bcm577 for future broarcom support
# 032215 rkw 0.9.77 added a label to bootstrap CLI ISO for easier detection - removed trailing ws
# 032315 nam 0.9.78 export images failing if not at end of args / --version was printing too much / ucs fixes
# 032315 nam 0.9.79 -export-image minor output format fixes
# 040115 rkw 0.9.80 added -boot-virsh - ability to run sunstone from the generated virsh
#                   added better export-image listing for compile
# 040115 rkw 0.9.81 was not creating bridges if bridges were deleted
# 040115 nam 0.9.82 docker fixes, don't try and install telnet etc
# 040215 nam 0.9.83 no tech support gather for exit 0 in bg mode
# 040215 nam 0.9.84 updated new CPU and memory models for VRR/VPE
# 040315 rkw 0.9.85 C-c now quits virsh mode, ws fix up
# 040315 nam 0.9.86 removed overlapping IP address assign chance
# 040315 nam 0.9.87 redhat support / more randomization for MACs
# 040315 rkw 0.9.88 make virsh mode display a labyrinth
# 040615 rkw 0.9.89 better mac address randomization
# 040615 nam 0.9.90 added disable bridges option for exporting images
#                   took out the ascii architecture map; making the help too
#                   long and liable to get out of date anwyay
# 040815 rkw 0.9.91 ability to launch two separate virsh sunstones
# 040815 nam 0.9.92 disable netfilter on bridges
# 040815 nam 0.9.93 added -disable-sudo option to try and run without any sudoisms or chmod +s
# 040815 rkw 0.9.94 added last modified user to -version output
# 040815 rkw 0.9.95 minor change of severity log in virsh generate
# 040815 nam 0.9.96 UCS image only needs on host nic for mgmt
# 040815 nam 0.9.97 smarter detection of lack of sudo
#                   diable tech support gather for ^C, too slow
#                   faster tech support generation
#                   suppress -export warning when outputdir="."
# 041115 asp 0.9.98 added vfio-pci support for passing pci devices
# 041315 nam 0.9.99 ported in NIC information printing from Jieming Wang
# 041315 nam 0.9.100 enable vhost-net on virtio dataplane interfaces
# 041315 nam 0.9.101 fixed comment on huge page def. mem; misc style fixes
# 041415 nam 0.9.102 added support for checksum offload disable
#                    added virsh support for csum offload
#                      (virsh xml validate fails however)
#                    added virsh support for vhost net
# 041515 rkw 0.9.103 changed virsh behavior to continue to try to launch even if validate fails
# 041515 aei 0.9.104 fixed restarting case to also include config ISO file
# 041615 rkw 0.9.105 added extra check for bootstrap cli in the -f case
#                    simplified logic to check for changed bootstrap and not create an ISO
#                    added commented out bootstrap virsh xml even if not requested
# 041615 rkw 0.9.106 fixed the bootstrap logic to work on an empty workdir - broken by .105
# 041615 nam 0.9.107 back to back ha topo added
# 042015 nam 0.9.108 added -slot for active/standby
# 042115 aei 0.9.109 added CVAC when sunstone restart
# 042115 rkw 0.9.110 change virsh xml to use qcow2 image
# 042115 nam 0.9.111 increase host NICS for UCS image
# 042215 nam 0.9.112 UCS remove vrouter flag, no longer needed
#                    Were not bringing up host bridges
# 042215 nam 0.9.113 end-list was being caught by "end" in config detector
# 042215 nam 0.9.114 keep it simple, just die on embedded end in config
# 042315 asp 0.9.115 add support for qemu page locking in memory for fast response
# 042415 rkw 0.9.116 change ovf template to use correct mgmnt interface naming
# 042515 nam 0.9.117 add default profile for UCS OVA building
# 042715 rkw 0.9.118 generate ova in the workspace, clean up correctly
# 042715 nam 0.9.119 tweak host bridges for larger mtu
# 042715 nam 0.9.120 add bios uuid support
# 042815 rkw 0.9.121 another ovf fix and remove -cloud option - which is now -vga
#ifdef CISCO
# 042815 nam 0.9.122 yaap, add support for n9kv
# 042815 nam 0.9.123 hide n9kv inside ifdef CISCO until GA
#endif
# 042815 rkw 0.9.124 better memory check for vrr profile
# 042815 asp 0.9.125 turn ksm off for vpe_performance profile
# 042815 asp 0.9.126 fix ksm off nits - renamed to --disable-ksm
# 042915 nam 0.9.127 allow over subscription of memory with -force
# 042915 nam 0.9.128 bug; was removing all ovf files in current dir...
# 043015 rkw 0.9.129 image name generation adds if needed: vga, dev and vrr suffixes
#                    vrr ovf template fix and suffix additions
#                    function name cleanup for consistency
# 043015 rkw 0.9.130 OVF Product URL fixup
# 050115 rkw 0.9.131 use correct XML for virsh serial ports
#                    add a qemu monitor port and connect to it
#                    remove optional args rm error and rename to mlockstring
# 050115 rkw 0.9.132 set virsh ports to 0 if exporting as customer will not want hard coded ports
#                    add comments for virsh console
# 050415 nam 0.9.133 support fractional mem values of Gb for calvados
# 050415 rkw 0.9.134 add a longchain topology
# 051415 aei 0.9.135 allowed different interface for CVAC disk other than virtio
# 051415 nam 0.9.136 QEMU 2.0 sysctl was not checked for sudo; ps grepping killing tee log process in -bg mode
# 051515 nam 0.9.137 bug, could assign IP addr to virbr0. added option to disable create of log files
# 052515 nam 0.9.138 added note on topology builder gui
# 052515             added -kernel option for booting XRVR
#                    added option to quieten symlink creation
# 060115 nam 0.9.139 added -machine pc-1.0 for dmidecode fixe
# 060315 nam 0.9.140 name change of images from sonstone- to ios-xrv9k-
# 060815 nam 0.9.141 prefer dmidecode to get uuid, do not modify iso for it
# 060915 nam 0.9.142 telnet port collision not working
# 060915 nam 0.9.143 more help on common exit errors, from Alpesh's cheat sheet
# 070615 nam 0.9.144 if virsh xml exists, reuse the file so we keep the uuid
# 070615             save the uuid in workspace so we can reuse on reruns
# 071115             vios bootstrap cfg changes
# 071315 nam 0.9.145 work around qemu -runas bug
# 071315 nam 0.9.146 do not install bridge-utils if -disable-bridges
# 071315 nam 0.9.147 clean was killing own process
# 071315 nam 0.9.148 check for child owned processes when cleaning
# 071315 nam 0.9.149 skip tee processes, causing problems with sanities
# 072315 nam 0.9.150 sunstone plugins
#                    tried to make log output quieter to highlight
#                    important logs
# 072315 nam 0.9.151 do not use XRUT QEMU on CENTOS
# 072315 nam 0.9.152 revert OPT_USER_QEMU_IMG_EXEC change; using wrong kvm still
# 072715 nam 0.9.153 try to use VXR qemu if found
# 072915 nam 0.9.154 -disable-logging added
# 072915 nam 0.9.155 more verbose error logs for older qemu
# 072915 nam 0.9.156 convert -pci eth into a PCI number for ease of use
# 072915 nam 0.9.157 fix for isoinfo output differences in passing when
#                    extracting isos
# 081315 nam 0.9.158 checksum offloading error reappeared with yocto 3.10 kernel
#                    and qemu 1.0; removed qemu version specific checks for this
#                    and disabling offloading for now
# 081315 nam 0.9.159 ucs image qemu monitor fix
# 082615 nam 0.9.160 pci_stub is not a module on centos
# 091215 nam 0.9.161 csum offloading was not disabled correctly
# 091415 rkw 0.9.162 virsh xml fixes: enable host passthrough, restart with virsh issue,
#                    remove lots of whitespace damage, added comments to the
#                    generated virsh xml.
# 091415 rkw 0.9.163 virsh xml fixes to run on centos os.
# 091715 nam 0.9.164 virsh xml add e1000 support
# 091715 nam 0.9.165 virsh xml add e1000 support added default support
# 092315 acl 0.9.166 Added tmux support.
# 092415 nam 0.9.166 kvm_ok preferred over kvm-ok for centos
# 092415 nam 0.9.167 csum off was not validating in virsh; removed
# 100115 nam 0.9.168 -disk option lost bootstrap iso
#                    -disable-disk-bootstrap-virtio added
# 101515 cdc 0.9.169 -sr-iov option and -pfif option for SR-IOV setup
# 102015 nam 0.9.170 export images broken again on ADS servers
# 102915 nam 0.9.171 fix merge damage with export images for build servers
# 103015 nam 0.9.172 choose workspace for tmpdir if not set (for exporting)
# 111015 cdc 0.9.173 add sysfs method for sr-iov configuration (other is "deprecated")
# 111115 nam 0.9.174 add numa and huge page support in virsh
# 111115 nam 0.9.175 memoryBacking not supported on older libvirt
# 111215 nam 0.9.176 check for suboptions in memoryBacking for old libvirt 1.2.2
#                    added some sanity checking of qemu-kvm
# 111315 nam 0.9.177 added multiqueue support
#                    added -runas option
#                    made tool exit after 5 mins of waiting for QEMU
#                    virsh alias name= was showing net0/1/2 twice
# 111715 nam 0.9.178 add support for forteville
# 112715 cdc 0.9.179 sr-iov remove pci-stup for sysfs and invert user vs mrxvt
# 112715 nam 0.9.180 virsh and qemu virtio serial support
#                    fixed virsh csum offloading syntac
# 120415 cdc 0.9.181 PCI devices are now part of virsh XML
# 120415 nam 0.9.182 Fix odd clean case where parent pid is 0
# 120415 cdc 0.9.183 reduce disk size to 45G
# 012616 bg  0.9.184 Add -numa-pxb and -numa-memdev for multisocket dataplane
# 020216 anl 0.9.185 Add -serial_number to set up XRv9k VM BIOS serial number
# 120415 cdc 0.9.186 add cpuset for cpu pinning in virsh xml generation
# 020516 acl 0.9.187 Fixed TMPDIR-related issue with launching tmux.
# 021116 nam 0.9.188 Smarter UCS ISO name detection
# 021129 nam 0.9.189 Changes to avoid removing or providing a mac for ztp bridge
# 030316 cdc 0.9.190 added promisc to PF for sr-iov for vlan scale
# 042016 gfm 0.9.191 unnecessary NIC reservations for IOSXRV platform
# 042016 taf 0.9.192 Updating OVF with correct id, product class and version
# 200416 cdc 0.9.193 remove disable ksm for RedHat hosts
# 042716 anl 0.9.194 Merge Bud's commit: Move -numa-memdev processing to remove hardcoded hugepage path
#                    Add checking if environment variable SHELL is properly set
#                    Update memory profile allocation example to keep in line with 6.0.1+
# 050716 rkw 0.9.195 ucs to iosxrv-x64 changes
# 050916 taf 0.9.196 bumping number of interfaces in ova file to 10
# 052316 gfm 0.9.197 missing quote mark introduced by 0.9.192
# 052516 gfm 0.9.198 don't lose OVF version when updating hardware.
# 052716 jm  0.9.199 added -rx-queues-per-port for dataplane in RSS mode
# 060616 taf 0.9.200 reduce data interfaces to 7 in OVA template as ESXi breaks
# 060916 gfm 0.9.201 dynamically add NICs to OVF template based on platform
# 062016 cdc 0.9.202 disable spoof check on VFs for SR-IOV
# 062016 cdc 0.9.203 allow SR-IOV on 40G and 1G as well
# 062016 jm  0.9.204 numa range validation for multisocket dataplane
# 082916 rkw 0.9.205 run sunstone.sh with an ISO found in either latest CI code
#                    or a throttle (currently 6.1.1)
# 083116 cdc 0.9.206 fixing issue with hardcoded p1p1 for spoofchk
# 090716 gfm 0.9.207 remove unneeded dependency on vmdktool
# 091416 rkw 0.9.208 fixed bug in post_read_options_guess_iso introduced by .205
# 101216 anl 0.9.209 merge branchs ss_ha and master
# 101816 pt  0.9.210 Fix for CSCvb19673: change default nic type for distr.mode
#                    Add code to tune taps/bridges post-launch for VIRSH mode
#                    Add 'sudo' when doing taskset CPU pin
# 101816 pt  0.9.211 Minor modification to previous fix to accommodate CentOS
# 102616 bg  0.9.212 Add -pxb for 64-port support
# 012518 bg  0.9.212 Add support for 128 ports (virtual ports) and virtual interface speed
# 111416 anl 0.9.213 Fix CSCvc01630 (-pci cannot be the last one for launching sunstone.sh)
# 111716 nam 0.9.214 -noterm option was killing qemu on exit, should leave terms running
# 161205 gfm 0.9.215 Fix NIC enumeration bug introduced in 0.9.201
# 161207 gfm 0.9.216 Don't embed local KVM path into exported virsh XML
# 170124 cdc 0.9.217 put .qcow2 in a sparse tar file, use less bw/spc with scp
# 170202 jm  0.9.218 use taskset -cp with cpu id, instead of bitmask, for cpu pinning
# 020317 nam 0.9.219 -loglevel added for kernel logging
#                    -export-images failing at nohup bash when ran with sudo
# 030917 cdc 0.9.220 added options to set VFs with a VLAN and rate
# 031017 nam 0.9.221 added format=raw checks for qcow disks
# 041817 cdc 0.9.222 removed qemu-* install recursive loops
# 041817 nam 0.9.223 format=raw was breaking xrvr boot with vmdk
# 052517 gfm 0.9.224 fixes for RHEL7.2 ADS and non-ADS environments
# 052617 gfm 0.9.225 don't try to use -cpu host if KVM is disabled
# 052617 jdh 0.9.226 On CEL 7 need -no-acpi to handle non-kvm hosts
# 071017 cdc 0.9.227 allow mcast traffic on virtual bridges
# 081517 cdc 0.9.228 increase default memory from 16G to 20G
# 092017 jdh 0.9.229 Convert qcow2 to compressed format, do not generate .tar
# 102417 cdc 0.9.230 allow flexible config of bridges for mcast
# 120417 jdh 0.0.231 allow lldp packets to pass through bridges
# 090718 cdc 0.0.232 disable multicast snooping by default

VERSION="0.9.232"
ORIGINAL_ARGS="$0 $@"
MYPID=$$

# Expand alias's in script (like 'pause_and_debug_params')
shopt -s expand_aliases

#
# Call like this: pause_and_debug_params "$BOOTSTRAP_NAME" "$BOOTSTRAP_FILE_NAME_ONLY"
#
pause_and_debug_params_()
{
    let z=1

    echo $# variables
    for var in "$@"
    do
        echo "Debug param $z: "$var""
        z=$((z+1))
    done
    read -n1 -rsp $'Press any key to continue or Ctrl+C to exit...\n'
}
alias pause_and_debug_params='echo "Line# $LINENO:"; pause_and_debug_params_ "$@"'

#
# Display $1 lines of the labyrinth for log separation
#
labyrinth()
{
    lines=$1
    shift

    column=$(tput cols)

    for  (( i=1; i<=$lines; i++ ))
    do
        for (( c=1; c<=$column; c++ ))
        do
            if [[ $(expr $RANDOM % 2 ) -eq 0 ]]; then
                echo -ne "${CYAN}\xE2\x95\xB1"
            else
                echo -ne "${CYAN}\xE2\x95\xB2"
            fi
        done
        echo $*${RESET}
    done
    echo
}

init_tool_defaults()
{
    #
    # Choose console automatically if not set
    #
    OPT_UI_LOG=0
    OPT_UI_NO_TERM=0
    OPT_UI_SCREEN=0
    OPT_UI_XTERM=0
    OPT_UI_GNOME_TERMINAL=0
    OPT_UI_KONSOLE=0
    OPT_UI_MRXVT=0
    OPT_UI_TMUX=0
    OPT_SNAPSHOT=""

    #
    # -net
    #
    OPT_NET_NAME=$LOGNAME
    OPT_NODE_NAME=

    #
    # --runas
    #
    OPT_ENABLE_RUNAS=1

    #
    # Assume sudo is permitted to be used
    #
    OPT_ENABLE_SUDO=1

    #
    # Enable network
    #
    OPT_ENABLE_NETWORK=1
    OPT_ENABLE_ADDRESS_ASSIGN=1
    OPT_ENABLE_SNOOPING=0
    OPT_ENABLE_QUERIER=2
    OPT_ENABLE_LLDP=0

    #
    # Create TAP interfsaces
    #
    OPT_ENABLE_TAPS=1

    #
    # Create bridges
    #
    OPT_ENABLE_BRIDGES=1

    #
    # Default configuration file
    #
    OPT_TOPO=sunstone.topo

    #
    # Linux limits the tap length annoyingly and we have to work around this
    #
    MAX_TAP_LEN=15

    CLEANUP_SRIOV=0
    CTX_SRIOV="x"
}

init_platform_defaults_iosxrv_32()
{
    PLATFORM_NAME_WITH_SPACES="Cisco IOS XRv 32 Bit"
    PLATFORM_NAME="IOS-XRVR"
    PLATFORM_name="ios-xrv"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES='"MgmtEth0/RP0/CPU0/0" "GigabitEthernet0/0/0/{0}"'
    PLATFORM_NETWORK_DESCS='"Management network" "Data network {1}"'
    PLATFORM_URL="http://www.cisco.com/go/iosxrv"

    OPT_PLATFORM_MEMORY_MB=8192
    OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"

    #
    # virtio is much faster for XRVR
    #
    NIC_DATA_INTERFACE=virtio-net-pci
    NIC_HOST_INTERFACE=virtio-net-pci

    #
    # Disable checksum offloading
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=0
    NIC_HOST_CSUM_OFFLOAD_ENABLE=0

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=0
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=0

    #
    # No calvados support
    #
    OPT_ENABLE_SER_3_4=0

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=1

    OPT_DATA_NICS=3
    OPT_HOST_NICS=1
    OPT_DATA_TAP_NAME=Xr
    OPT_HOST_TAP_NAME=Lx

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Put the mgmt eth on virbr0 for dhcp
    #
    OPT_HOST_VIRBR0_NIC="1"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=1

    #
    # Profiles not supported
    #
    OPT_ENABLE_HW_PROFILE=
}

init_platform_defaults_iosxrv()
{
    log "Setting platform defaults for Cisco IOS XRv64"
    PLATFORM_NAME_WITH_SPACES="Cisco IOS XRv 64-Bit"
    PLATFORM_NAME="IOSXRV"
    PLATFORM_name="ios-xrv-x64"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES='"MgmtEth0/RP0/CPU0/0" "GigabitEthernet0/0/0/{0}"'
    PLATFORM_NETWORK_DESCS='"Management network" "Data network {1}"'
    PLATFORM_URL="http://www.cisco.com/go/iosxrv"

    OPT_PLATFORM_DISK_SIZE_GB=45G
    OPT_PLATFORM_MEMORY_MB=4096
    OPT_PLATFORM_SMP="-smp cores=2,threads=1,sockets=1"

    #
    # virtio is much faster for XRVR
    #
    NIC_DATA_INTERFACE=virtio-net-pci
    NIC_HOST_INTERFACE=virtio-net-pci

    #
    # Disable checksum offloading
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=0
    NIC_HOST_CSUM_OFFLOAD_ENABLE=0

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=1
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=1

    #
    # No calvados support
    #
    OPT_ENABLE_SER_3_4=1

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=1

    OPT_DATA_NICS=3
    #
    # Default to 1 host NIC (MgmtEth).
    # This may be adjusted in post_read_options_init_net_vars_iosxrv()
    #
    OPT_HOST_NICS=1
    OPT_DATA_TAP_NAME=Xr
    OPT_HOST_TAP_NAME=Lx

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Put the mgmt eth on virbr0 for dhcp
    # May be overridden by post_read_options_init_net_vars_iosxrv()
    #
    OPT_HOST_VIRBR0_NIC="1"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=1

    # Baked suffix. As this may change - create a variable so it can
    # be changed in one place
    BAKED_SUFFIX=".baked"

    #
    # On by default for now
    #
    OPT_ENABLE_DEV_MODE=1
}

post_read_options_platform_defaults_iosxrv()
{
    if [[ "$PLATFORM_NAME" != "IOSXRV" ]]; then
        return
    fi

    #
    # For some reason, IOSXRV ships with no console support which makes
    # it hard to debug on boot. Add it back.
    #
    add_grub_line "serial --unit=0 --speed=115200"
    add_grub_line "terminal serial"
    append_linux_cmd "__vrouter=true"
    append_linux_cmd "console=ttyS0"
}

#ifdef CISCO
init_platform_defaults_n9kv()
{
    PLATFORM_NAME_WITH_SPACES="Cisco Nexus 9kv"
    PLATFORM_NAME="n9kv"
    PLATFORM_name="n9kv"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES='"mgmt0" "Ethernet2/{1}"'
    PLATFORM_NETWORK_DESCS='"Management network" "Data network {1}"'
    PLATFORM_URL="http://www.cisco.com/go/nexus"


    OPT_PLATFORM_MEMORY_MB=12290
    OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"

    #
    # virtio is much faster for XRVR
    #
    NIC_DATA_INTERFACE=vmxnet3
    NIC_HOST_INTERFACE=vmxnet3

    #
    # Checksum offloading, default
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=1
    NIC_HOST_CSUM_OFFLOAD_ENABLE=1

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=0
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=0

    #
    # No calvados support
    #
    OPT_ENABLE_SER_3_4=0

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=1

    OPT_DATA_NICS=3
    OPT_HOST_NICS=1
    OPT_DATA_TAP_NAME=9k
    OPT_HOST_TAP_NAME=Mg

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Put the mgmt eth on virbr0 for dhcp
    #
    OPT_HOST_VIRBR0_NIC="1"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=1

    # Baked suffix. As this may change - create a variable so it can
    # be changed in one place
    BAKED_SUFFIX=".baked"

    #
    # On by default for now
    #
    OPT_ENABLE_DEV_MODE=1
}

post_read_options_platform_defaults_n9kv()
{
    if [[ "$PLATFORM_NAME" != "n9kv" ]]; then
        return
    fi
}
#endif

init_platform_defaults_iosv()
{
    PLATFORM_NAME_WITH_SPACES="Cisco IOSv"
    PLATFORM_NAME="vIOS"
    PLATFORM_name="iosv"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES="GigabitEthernet0/{0}"
    PLATFORM_NETWORK_DESCS='"Data network {1}"'
    PLATFORM_URL=""

    OPT_PLATFORM_MEMORY_MB=1024
    OPT_PLATFORM_SMP=

    NIC_DATA_INTERFACE=e1000
    NIC_HOST_INTERFACE=e1000

    #
    # Checksum offloading, default
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=1
    NIC_HOST_CSUM_OFFLOAD_ENABLE=1

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=1
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=1

    #
    # No calvados support
    #
    OPT_ENABLE_SER_3_4=0

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=0

    OPT_DATA_NICS=5
    OPT_HOST_NICS=0
    OPT_DATA_TAP_NAME=Io

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Put the mgmt eth on virbr0 for dhcp
    #
    OPT_HOST_VIRBR0_NIC="1"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=0

    #
    # Profiles not supported
    #
    OPT_ENABLE_HW_PROFILE=
}

init_platform_defaults_linux()
{
    PLATFORM_NAME_WITH_SPACES="Linux"
    PLATFORM_NAME="Linux"
    PLATFORM_name="linux"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES="eth{0}"
    PLATFORM_NETWORK_DESCS='"Data network {1}"'
    PLATFORM_URL=""

    OPT_PLATFORM_MEMORY_MB=8192
    OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"

    #
    # virtio is much faster for linux
    #
    NIC_DATA_INTERFACE=virtio-net-pci
    NIC_HOST_INTERFACE=virtio-net-pci

    #
    # Checksum offloading, default
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=1
    NIC_HOST_CSUM_OFFLOAD_ENABLE=1

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=1
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=1

    #
    # No calvados support
    #
    OPT_ENABLE_SER_3_4=0

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=1

    OPT_DATA_NICS=3
    OPT_HOST_NICS=3
    OPT_DATA_TAP_NAME=Li
    OPT_HOST_TAP_NAME=Lx

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Put the mgmt eth on virbr0 for dhcp
    #
    OPT_HOST_VIRBR0_NIC="1"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=1

    #
    # Profiles not supported
    #
    OPT_ENABLE_HW_PROFILE=
}

init_platform_defaults_ios_xrv_9000()
{
    PLATFORM_NAME_WITH_SPACES="Cisco IOS XRv 9000"
    PLATFORM_NAME="IOS-XRv-9000"
    PLATFORM_name="ios-xrv9000"
    PLATFORM_VIRSH_TITLE="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_ID="com.cisco.${PLATFORM_name}"
    PLATFORM_OVA_CLASS="com.cisco.${PLATFORM_name}"
    PLATFORM_NIC_NAMES='"MgmtEth0/RP0/CPU0/0" "CtrlEth" "DevEth" "GigabitEthernet0/0/0/{0}"'
    PLATFORM_NETWORK_DESCS='"Management network" "Control-ethernet network" "Development network" "Data network {1}"'
    PLATFORM_URL="http://www.cisco.com/c/en/us/support/routers/ios-xrv-9000-router/tsd-products-support-series-home.html"

    #
    # Will be overriden with profile extension possibly
    #
    OVA_PLATFORM_NAME="${PLATFORM_NAME}"

    PLATFORM_LXC_DOMAINS=( calvados xr uvf )

    NIC_DATA_INTERFACE=e1000
    NIC_HOST_INTERFACE=virtio-net-pci

    #
    # Checksum offloading, disable
    #
    NIC_DATA_CSUM_OFFLOAD_ENABLE=0
    NIC_HOST_CSUM_OFFLOAD_ENABLE=0

    #
    # Only set this if the early options did not override it.
    #
    if [[ "$OPT_ENABLE_HW_PROFILE" = "" ]]; then
        OPT_ENABLE_HW_PROFILE=vpe
    fi

    # Baked suffix. As this may change - create a variable so it can
    # be changed in one place
    BAKED_SUFFIX=".baked"

#ifdef CISCO
    #
    # On by default for now
    #
    OPT_ENABLE_DEV_MODE=1

    #
    # Sim mode for booting on VXR
    #
    OPT_ENABLE_SIM_MODE=0

    #
    # No docker feature by default
    #
    OPT_DOCKER_FEATURE=0
#endif

    #
    # Off by default for now
    #
    OPT_ENABLE_VGA=0

    #
    # Serial port virtio support?
    #
    OPT_ENABLE_SERIAL_VIRTIO=0

    #
    # Disk virtio support?
    #
    OPT_ENABLE_DISK_VIRTIO=1
    OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=1

    #
    # 3rd/4th tty
    #
    OPT_ENABLE_SER_3_4=1

    #
    # --enable-kvm
    #
    OPT_ENABLE_KVM=1
    OPT_ENABLE_DAEMONIZE=1
    OPT_ENABLE_MONITOR=1

    #
    # --smp
    #
    OPT_ENABLE_SMP=1

    OPT_DATA_NICS=3
    OPT_HOST_NICS=3
    OPT_DATA_TAP_NAME=Xr
    OPT_HOST_TAP_NAME=Lx

    OPT_MTU=10000
    OPT_TXQUEUELEN=10000

    #
    # Connect eth2 (index 3) to virbr0.
    #
    # Connect eth0 (index 1) for mgmt eth for dhcp.
    #
    OPT_HOST_VIRBR0_NIC="3"

    #
    # --enable-numa
    #
    OPT_ENABLE_NUMA_CHECKING=1

    #
    # --guest-hugepages
    #
    OPT_GUEST_HUGEPAGE=3072

    #
    # Cache mode for disks.
    #
    # Only unsafe mode gave real improvements in baking.
    #
    #OPT_DISK_CACHE="cache=unsafe,"
    #OPT_DISK_CACHE="cache=none,"
    #OPT_DISK_CACHE="cache=directsync,"
    #OPT_DISK_CACHE="cache=writethrough,"
    #
    # fyi writeback is the default beyond for qemu >= 1.2
    #
    #OPT_DISK_CACHE="cache=writeback,"
    OPT_DISK_CACHE=

    #
    # Deadline is meant to be good for nested KVM. Didn't see much change.
    #
    #add_linux_cmd "elevator=deadline"
    #add_linux_cmd "elevator=cfq" # default for RHEL
    #add_linux_cmd "elevator=as"
    #
    # noop is now being used as default in xrv9k
    #
    #add_linux_cmd "elevator=noop"

    #
    # io=native is meant to be good for nested KVM. Didn't see much change.
    #
    #add_linux_cmd "io=native"
    #add_linux_cmd "io=threads"
}

pre_qemu_start_platform_defaults_ios_xrv_9000()
{
    if [[ "$PLATFORM_NAME" != "IOS-XRv-9000" ]]; then
        return
    fi

    if [[ "$OPT_ENABLE_KVM" -eq 1 ]]; then
        #
        # To pass all available host processor features to the guest:
        # Only usable when KVM is enabled
        #
        $KVM_EXEC -cpu help > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            $KVM_EXEC -cpu help | grep -q "\<host\>"
            if [[ $? -eq 0 ]]; then
                add_qemu_cmd "-cpu host"
            fi
        else
            add_qemu_cmd "-cpu host"
        fi
    fi
}

pre_qemu_start_platform_defaults_iosxrv()
{
    if [[ "$PLATFORM_NAME" != "IOSXRV" ]]; then
        return
    fi

    #
    # For some odd reason without this, qemu monitor does not start...
    #

    if [[ "$OPT_ENABLE_KVM" -eq 1 ]]; then
        #
        # To pass all available host processor features to the guest:
        # Only usable when KVM is enabled
        #
        $KVM_EXEC -cpu help > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            $KVM_EXEC -cpu help | grep -q "\<host\>"
            if [[ $? -eq 0 ]]; then
                add_qemu_cmd "-cpu host"
            fi
        else
            add_qemu_cmd "-cpu host"
        fi
    fi
}

post_read_options_platform_defaults_ios_xrv_9000()
{
    if [[ "$PLATFORM_NAME" != "IOS-XRv-9000" ]]; then
        return
    fi

    #
    # Pass the guest hugepage request
    #
    if [[ "$OPT_GUEST_HUGEPAGE" != "" ]]; then
         add_guest_hugepage $OPT_GUEST_HUGEPAGE
    fi

    #
    # If exporting images, save a copy of the original ISO now
    #
    if [[ "$OPT_EXPORT_IMAGES" != "" ]]; then
        log_debug "Output dir $OUTPUT_DIR"

        local file=`basename $OPT_BOOT_ISO`
        if [[ -f $OUTPUT_DIR/$file ]] ; then
            diff -q $OPT_BOOT_ISO $OUTPUT_DIR/$file
            if [[ $? -ne 0 ]]; then
                cp -f --no-preserve=mode,ownership $OPT_BOOT_ISO $OUTPUT_DIR
            else
                log_debug "File exists, no need to copy"
            fi
        else
            cp -f --no-preserve=mode,ownership $OPT_BOOT_ISO $OUTPUT_DIR
        fi
    fi
}

post_read_options_platform_defaults()
{
    post_read_options_platform_defaults_iosxrv
#ifdef CISCO
    post_read_options_platform_defaults_n9kv
#endif
    post_read_options_platform_defaults_ios_xrv_9000
}

init_platform_hw_profile_ios_xrv_9000()
{
    local PLATFORM_MEMORY=
    local profile=

    if [[ $OPT_ENABLE_HW_PROFILE = "vrr" ]]; then
        profile=-vrr
    elif [[ $OPT_ENABLE_HW_PROFILE = "vpe_performance" ]]; then
        profile=-vpe_performance
    elif [[ $OPT_ENABLE_HW_PROFILE = "vpe_perf_red_hat" ]]; then
        profile=-vpe_perf_red_hat
    elif [[ $OPT_ENABLE_HW_PROFILE = "vpe" ]]; then
        profile=-vpe
    elif [[ $OPT_ENABLE_HW_PROFILE = "lite" ]]; then
        profile=-lite
    elif [[ $OPT_ENABLE_HW_PROFILE = "" ]]; then
        OPT_ENABLE_HW_PROFILE="vpe"
        profile=-vpe
    else
        profile=-user_defined
    fi

    OVA_PLATFORM_NAME="${PLATFORM_NAME}${profile}"

    if [[ "$OPT_ENABLE_HW_PROFILE" = "vpe_performance" ]]; then
        #
        # VPE performance profile
        #
        log "VPE (Virtual Provider Edge profile) - Default"

        OPT_PLATFORM_MEMORY_MB=24576
        OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
        OPT_ENABLE_HW_PROFILE_CPU="1/1/0-1,2-7"
        OPT_NUMA_NODES=0
        OPT_MIN_NUMA_NODE=0
        OPT_MAX_NUMA_NODE=0
        OPT_ENABLE_HW_PROFILE="vpe"
        OPT_KSMOFF=1

        #
        # For future ivestigation
        #
        # append_linux_cmd "nohz_full=1 rcu_nocbs=1"
        #
        # relevant flags:
        # CONFIG_RCU_NOCB_CPU
        # CONFIG_RCU_FAST_NO_HZ
        # CONFIG_NO_HZ_FULL
        #
        # append_linux_cmd "acpi=off"   fails as we see only one cpu
        # append_linux_cmd "noapic"     fails as we see only one cpu
        # append_linux_cmd "nolapic"    fails as we see only one cpu

    elif [[ "$OPT_ENABLE_HW_PROFILE" = "vpe_perf_red_hat" ]]; then

        #
        # VPE performance profile for RedHat
        #
        log "VPE RedHat (Virtual Provider Edge profile)"

        OPT_PLATFORM_MEMORY_MB=24576
        OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
        OPT_ENABLE_HW_PROFILE_CPU="1/1/0-1,2-7"
        OPT_NUMA_NODES=0
        OPT_MIN_NUMA_NODE=0
        OPT_MAX_NUMA_NODE=0
        OPT_NUMA_RED_HAT="true"
        OPT_ENABLE_HW_PROFILE="vpe"

    elif [[ "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        #
        # VRR profile
        #
        log "VRR (Virtual Route Reflector profile)"

        OPT_PLATFORM_MEMORY_MB=24576
        OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
    elif [[ "$OPT_ENABLE_HW_PROFILE" = "lite" ]]; then
        #
        # Lite profile
        #
        log "Lite (Virtual Provider Edge Lite profile)"

        OPT_PLATFORM_MEMORY_MB=4096
        OPT_PLATFORM_SMP="-smp cores=2,threads=1,sockets=1"
    else
        #
        # VPE non performance profile
        #
        log "VPE (Virtual Provider Edge profile) - Default"

        OPT_PLATFORM_MEMORY_MB=20480
        OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"
    fi

    #
    # Check available memory
    #
    # if too low for vPE - quit
    # if vRR is requested and too low, then switch to a vPE profile
    # including generated OVA and Virsh XML
    #
    local FREE=`free -tm | grep Total | awk '{print $2}'`

    if [[ "$FREE" -lt 24576 && "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        log "Memory check: '${FREE}MB' available memory, requesting '${OPT_PLATFORM_MEMORY_MB}MB'"
        log "Using Default vPE profile: available memory '${FREE}MB' is too low to orchestrate a vRR image"
        log "VPE (Virtual Provider Edge profile) - Default"
        OPT_PLATFORM_MEMORY_MB=20480
        OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"
        OPT_ENABLE_HW_PROFILE=vpe
    fi

    if [[ "$OPT_PLATFORM_MEMORY_MB" = "" ]]; then
        die "Tool bug, memory is not set"
    fi

    if [[ "$OPT_PLATFORM_SMP" = "" ]]; then
        die "Tool bug, smp is not set"
    fi
}

init_platform_hw_profile_iosxrv()
{
    local PLATFORM_MEMORY=
    local profile=

    if [[ $OPT_ENABLE_HW_PROFILE = "vrr" ]]; then
        profile=-vrr
    elif [[ $OPT_ENABLE_HW_PROFILE = "" ]]; then
        OPT_ENABLE_HW_PROFILE="vrr"
        profile=-vrr
    else
        profile=-user_defined
    fi

    OVA_PLATFORM_NAME="${PLATFORM_NAME}${profile}"

    if [[ "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        #
        # VRR profile
        #
        log "VRR (Virtual Route Reflector profile)"

        OPT_PLATFORM_MEMORY_MB=24576
        OPT_PLATFORM_SMP="-smp cores=8,threads=1,sockets=1"
    fi

    if [[ "$OPT_PLATFORM_MEMORY_MB" = "" ]]; then
        die "Tool bug, memory is not set"
    fi

    if [[ "$OPT_PLATFORM_SMP" = "" ]]; then
        die "Tool bug, smp is not set"
    fi
}

#ifdef CISCO
init_platform_hw_profile_n9kv()
{
    local PLATFORM_MEMORY=
    local profile=

    if [[ $OPT_ENABLE_HW_PROFILE = "vrr" ]]; then
        profile=-vrr
    elif [[ $OPT_ENABLE_HW_PROFILE = "" ]]; then
        OPT_ENABLE_HW_PROFILE="vrr"
        profile=-vrr
    else
        profile=-user_defined
    fi

    OVA_PLATFORM_NAME="${PLATFORM_NAME}${profile}"

    if [[ "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        #
        # VRR profile
        #
        log "VRR (Virtual Route Reflector profile)"

        OPT_PLATFORM_MEMORY_MB=12290
        OPT_PLATFORM_SMP="-smp cores=4,threads=1,sockets=1"
    fi

    if [[ "$OPT_PLATFORM_MEMORY_MB" = "" ]]; then
        die "Tool bug, memory is not set"
    fi

    if [[ "$OPT_PLATFORM_SMP" = "" ]]; then
        die "Tool bug, smp is not set"
    fi
}
#endif

init_platform_hw_profile_()
{
    case "$PLATFORM_NAME" in
    *XRv-9000*)
        init_platform_hw_profile_ios_xrv_9000
        ;;
    *IOSXRV*)
        init_platform_hw_profile_iosxrv
        ;;
#ifdef CISCO
    *n9kv*)
        init_platform_hw_profile_n9kv
        ;;
#endif
    *)
        die "Platform $PLATFORM_NAME does not support profile $OPT_ENABLE_HW_PROFILE"
        ;;
    esac
}

init_platform_hw_profile()
{
    #
    # Check hw profile type
    #
    if [[ "$OPT_ENABLE_HW_PROFILE" = "vpe" ]] ||
       [[ "$OPT_ENABLE_HW_PROFILE" = "vpe_performance" ]] ||
       [[ "$OPT_ENABLE_HW_PROFILE" = "vpe_perf_red_hat" ]] ||
       [[ "$OPT_ENABLE_HW_PROFILE" = "lite" ]] ||
       [[ "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        init_platform_hw_profile_
    else
        #
        # Check and see if the profile is a file.
        # If the profile does not exist on disk either, warn the user.
        # We still pass the name through to grub though.
        #
        if [[ -f $OPT_ENABLE_HW_PROFILE ]]; then
            log "Sourcing hw profile template: $OPT_ENABLE_HW_PROFILE"
            . $OPT_ENABLE_HW_PROFILE
        else
            #
            # Take care, XRVR and others do not have profiles
            #
            if [[ "$OPT_ENABLE_HW_PROFILE" != "" ]]; then
                err "Unknown hw profile: $OPT_ENABLE_HW_PROFILE"
                warn "Supported profiles:"
                warn "  vpe (Virtual Private Edge) - default"
                warn "  vpe_performance (Virtual Private Edge) - tuned high performance"
                warn "  vpe_perf_red_hat (Virtual Private Edge) - tuned high performance for RedHat"
                warn "  vrr (Virtual Route Reflector mode)"
                warn "  lite (Virtual Private Edge lite)"
                warn "  Defaulting to: vpe (Virtual Provider Edge)"
                OPT_ENABLE_HW_PROFILE="vpe"
                init_platform_hw_profile_
            fi
        fi
    fi
}

install_ubuntu()
{
    local PACKAGE=$1

    if [[ "$is_ubuntu" = "" ]]; then
        return
    fi

    banner "Attempting to install $PACKAGE"

    trace sudo apt-get install $PACKAGE
    if [[ $? -ne 0 ]]; then
        err "Package install failed for $PACKAGE"
        err "Will try to continue, but this may be a critical error"
        err "Try 'apt-get update' which *may* resolve this error"
        sleep 10
    fi
}

install_redhat_family()
{
    if [[ "$is_redhat_family" = "" ]]; then
        return
    fi

    trace yum -y install $*
    if [[ $? -ne 0 ]]; then
        banner "Failed to install. Try running the following as root:"
        echo "yum -y install $*"
    else
        return
    fi

#ifdef CISCO
    #
    # If on cisco workspace?
    #
    for i in \
        /auto/nsstg-tools-hard/bin/sunstone/prepare_qemu_env.sh \
        /auto/rp_dt_panini/jiemiwan/sunstone/prepare_qemu_env.sh
    do
        if [[ -x $i ]]; then
            banner "Or try running the following as root:"
            echo "$i"
        fi
    done
#endif

    exit 1
}

install_upgrade_pip()
{
    which pip &>/dev/null
    if [[ $? -ne 0 ]]; then
        install_package_help pip binary pip
    fi

    sudo_check_trace pip install --upgrade $*
    if [[ $? -ne 0 ]]; then
        die "Install/upgrade of '$*' failed"
    fi
}

install_package_help()
{
    local TARGET=$1
    local TYPE=$2
    local WHAT=$3

    warn "$WHAT is not installed. I will try to install $TARGET to resolve this."

    case $TARGET in
    *qemu*|*kvm*)
        install_ubuntu qemu-system
        install_redhat_family "@virt*"
        ;;

    *brctl*|*tunctl*|*ifconfig*)
        if [[ "$OPT_ENABLE_BRIDGES" = "1" ]]; then
            install_ubuntu bridge-utils
            install_ubuntu uml-utilities
            install_redhat_family bridge-utils tunctl
        fi
        ;;

    gnome-terminal)
        install_ubuntu gnome-terminal
        install_redhat_family gnome-terminal
        ;;

    konsole)
        install_ubuntu konsole
        install_redhat_family konsole
        ;;

    mrxvt)
        install_ubuntu mrxvt
        install_redhat_family mrxvt
        ;;

    xterm)
        install_ubuntu xterm
        install_redhat_family xorg-x11-xauth xterm
        ;;

    screen)
        install_ubuntu screen
        install_redhat_family screen
        ;;

    tmux)
        install_ubuntu tmux
        install_redhat_family tmux
        ;;

    mkisofs)
        install_ubuntu genisoimage
        install_redhat_family genisoimage
        ;;

    libvirt-bin)
        install_ubuntu libvirt-bin
        install_redhat_family libvirt-bin
        ;;

    pip)
        # https://packaging.python.org/install_requirements_linux/
        install_ubuntu python-pip
        # this should work on fedora but may fail on centos/rhel
        install_redhat_family python-setuptools python-pip python-wheel
        ;;

    cot)
        install_upgrade_pip cot
        ;;
    esac

    #
    # If installing a binary, does it now exist? Packages, we cannot easily
    # check and rely on the caller to do this.
    #
    if [[ "$TYPE" = "binary" ]]; then
        which $TARGET
        if [[ $? -ne 0 ]]; then
            err "$TARGET is not installed. Will try to continue."
            sleep 10
        fi
    fi
}

sudo_check()
{
    local PROG=$1

    if [[ ! -e $PROG ]]; then
        local PATH_PROG=`which $PROG`
        if [[ ! -e $PATH_PROG ]]; then
            err "Executable $PROG does not exist"
            false
            return
        fi

        PROG=$PATH_PROG
    fi

    if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
        $*
        return
    fi

    if [[ -u $PROG ]]; then
        $*
    else
        chmod +s $PROG &>/dev/null

        if [[ -u $PROG ]]; then
            $*
        else
            if [[ "$is_redhat_family" != "" ]]; then
                $*
            else
                sudo $*
                return
            fi
        fi
    fi

    RET=$?
    if [[ $? -eq 0 ]]; then
        return $RET
    fi

    if [[ "$is_redhat_family" != "" ]]; then
        return $RET
    fi

    sudo $*
}

sudo_check_trace()
{
    local PROG=$1

    if [[ ! -e $PROG ]]; then
        local PATH_PROG=`which $PROG`
        if [[ ! -e $PATH_PROG ]]; then
            err "Executable $PROG does not exist"
            false
            return
        fi

        PROG=$PATH_PROG
    fi

    if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
        trace $*
        return
    fi

    if [[ -u $PROG ]]; then
        trace $*
    else
        chmod +s $PROG &>/dev/null

        if [[ -u $PROG ]]; then
            trace $*
        else
            if [[ "$is_redhat_family" != "" ]]; then
                trace $*
            else
                trace sudo $*
                return
            fi
        fi
    fi

    #
    # Try with sudo if allowed
    #
    RET=$?
    if [[ $RET -ne 0 ]]; then
        trace sudo $*
        RET=$?
    fi

    return $RET
}

sudo_check_trace_to()
{
    local CMD="$1"
    local FILE="$2"

    sudo_check $CMD 2>&1 >$FILE
    RET=$?

    if [[ $RET -ne 0 ]]; then
        cat $FILE
    fi

    cat $FILE >> $LOG_DIR/$PROGRAM.log
    return $RET
}

assert_root()
{
    if [[ "$(id -u)" != "0" ]]; then
        echo "INFO: For more detailed results, you should run this as root"
        echo "HINT:   sudo $0"
    fi
}

verdict()
{
        # Print verdict
        if [[ "$1" = "0" ]]; then
            echo "KVM acceleration can be used"
        else
            echo "KVM acceleration can NOT be used"
        fi
}

kvm_ok()
{
    # check cpu flags for capability
    virt=$(egrep -m1 -w '^flags[[:blank:]]*:' /proc/cpuinfo | egrep -wo '(vmx|svm)') || true
    [ "$virt" = "vmx" ] && brand="intel"
    [ "$virt" = "svm" ] && brand="amd"

    if [[ -z "$virt" ]]; then
        echo "INFO: Your CPU does not support KVM extensions"
        assert_root
        verdict 1
        return 1
    fi

    # Now, check that the device exists
    if [[ -e /dev/kvm ]]; then
        echo "INFO: /dev/kvm exists"
        verdict 0
        return 0
    else
        echo "INFO: /dev/kvm does not exist"
        echo "HINT:   sudo modprobe kvm_$brand"
    fi

    assert_root

    # Prepare MSR access
    msr="/dev/cpu/0/msr"
    if [[ ! -r "$msr" ]]; then
            modprobe msr
    fi

    if [[ ! -r "$msr" ]]; then
        echo "You must be root to run this check." >&2
        return 1
    fi

    echo "INFO: Your CPU supports KVM extensions"

    disabled=0
    # check brand-specific registers
    if [[ "$virt" = "vmx" ]]; then
            BIT=$(rdmsr --bitfield 0:0 0x3a 2>/dev/null || true)
            if [[ "$BIT" = "1" ]]; then
                    # and FEATURE_CONTROL_VMXON_ENABLED_OUTSIDE_SMX clear (no tboot)
                    BIT=$(rdmsr --bitfield 2:2 0x3a 2>/dev/null || true)
                    if [[ "$BIT" = "0" ]]; then
                            disabled=1
                    fi
            fi

    elif [[ "$virt" = "svm" ]]; then
            BIT=$(rdmsr --bitfield 4:4 0xc0010114 2>/dev/null || true)
            if [[ "$BIT" = "1" ]]; then
                    disabled=1
            fi
    else
            echo "FAIL: Unknown virtualization extension: $virt"
            verdict 1
            return 1
    fi

    if [[ "$disabled" -eq 1 ]]; then
            echo "INFO: KVM ($virt) is disabled by your BIOS"
            echo "HINT: Enter your BIOS setup and enable Virtualization Technology (VT),"
            echo "      and then hard poweroff/poweron your system"
            verdict 1
            return 0
    fi

    verdict 0
    return 0
}

post_read_options_init_disk_vars()
{
    DISK1_NAME=disk1

    if [[ "$OPT_PLATFORM_DISK_SIZE_GB" = "" ]]; then
        DISK1_SIZE=45G
    else
        DISK1_SIZE=$OPT_PLATFORM_DISK_SIZE_GB
    fi

    if [[ "$OPT_INSTALL_CREATE_QCOW2" != "" ]]; then
        DISK_TYPE=qcow2
    else
        DISK_TYPE=raw
    fi

    DISK1=${WORK_DIR}${DISK1_NAME}.$DISK_TYPE
}

post_read_options_init_net_vars_iosxrv()
{
    if [[ "$PLATFORM_NAME" != "IOSXRV" ]]; then
        return
    fi

#ifdef CISCO
    if [[ "$OPT_ENABLE_DEV_MODE" = "1" ]]; then
        # dev mode implies fabric as well. Fabric is NIC #2 and host is NIC #3
        OPT_HOST_NICS=3
        OPT_HOST_VIRBR0_NIC="3"
        PLATFORM_NIC_NAMES='"MgmtEth0/RP0/CPU0/0" "Fabric" "DevEth" "GigabitEthernet0/0/0/{0}"'
        PLATFORM_NETWORK_DESCS='"Management network" "Control-ethernet network" "Development network" "Data network {1}"'
    elif [[ "$OPT_ENABLE_FABRIC_NIC" = "1" ]]; then
        OPT_HOST_NICS=2
        PLATFORM_NIC_NAMES='"MgmtEth0/RP0/CPU0/0" "Fabric" "GigabitEthernet0/0/0/{0}"'
        PLATFORM_NETWORK_DESCS='"Management network" "Control-ethernet network" "Data network {1}"'
    else
        OPT_HOST_NICS=1
    fi
#endif
}

post_read_options_init_net_vars()
{
    post_read_options_init_net_vars_iosxrv

    #
    # Keep the name lengths here less than SPACE_NEEDED_FOR_SUFFIX
    #
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        TAP_DATA_ETH[$i]=${OPT_NODE_NAME}${OPT_DATA_TAP_NAME}$i
        BRIDGE_DATA_ETH[$i]=${OPT_NET_NAME}Br$i
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        TAP_HOST_ETH[$i]=${OPT_NODE_NAME}${OPT_HOST_TAP_NAME}$i
        BRIDGE_HOST_ETH[$i]=${OPT_NET_NAME}LxBr$i
    done

    #
    # Override the NIC if we are connecting to the virtual bridge
    #
    if [[ "$OPT_HOST_VIRBR0_NIC" != "" ]]; then
        for i in $OPT_HOST_VIRBR0_NIC
        do
            BRIDGE_HOST_ETH[$i]="virbr0"
        done
    fi

    for topo in $OPT_TOPO
    do
        if [[ -f $topo ]]; then
            log_debug "Sourcing template: $topo"
            . $topo
        fi
    done

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        log_debug "TAP_DATA_ETH[$i]="${OPT_NODE_NAME}${OPT_DATA_TAP_NAME}$i
        log_debug "BRIDGE_DATA_ETH[$i]="${OPT_NET_NAME}Br$i
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        log_debug "TAP_HOST_ETH[$i]="${OPT_NODE_NAME}${OPT_HOST_TAP_NAME}$i
        log_debug "BRIDGE_HOST_ETH[$i]="${OPT_NET_NAME}LxBr$i
    done
}

post_read_options_init_tty_vars()
{
    TTY0_NAME="QEMU"
    TTY1_NAME="Xr"
    TTY2_NAME="XrAux"
    TTY3_NAME="Admin"
    TTY4_NAME="AdAux"

    QEMU_NAME_LONG="QEMU monitor        "
    TTY1_NAME_LONG="Host/IOS XR Console "
    TTY2_NAME_LONG="IOS XR Aux console  "
    TTY3_NAME_LONG="Calvados Console    "
    TTY4_NAME_LONG="Calvados Aux console"

    if [[ "$OPT_ENABLE_VGA" = "1" ]]; then
        append_linux_cmd "__cloud=true"

        TTY1_NAME="XrAux"
        TTY1_NAME_LONG="IOS XR Aux console  "

        TTY2_NAME="Admin"
        TTY2_NAME_LONG="Calvados Console    "

        TTY3_NAME="AdAux"
        TTY3_NAME_LONG="Calvados Aux console"

        TTY4_NAME="NA"
        TTY4_NAME_LONG="(Host shell NA)     "
    fi

    case $PLATFORM_name in
        *linux*)
            TTY1_NAME="Con"
            TTY1_NAME_LONG="Linux console port  "
            TTY2_NAME="Aux"
            TTY2_NAME_LONG="Linux aux port      "
        ;;
        *vios*)
            TTY1_NAME="Vios"
            TTY1_NAME_LONG="VIOS console        "
            TTY2_NAME="Aux"
            TTY2_NAME_LONG="VIOS aux port       "
        ;;
#ifdef CISCO
        *n9kv*)
            TTY1_NAME="Con"
            TTY1_NAME_LONG="n9kv console        "
            TTY2_NAME="Aux"
            TTY2_NAME_LONG="n9kv aux port       "
        ;;
#endif
    esac

#ifdef CISCO
    if [[ "$OPT_ENABLE_SIM_MODE" = "1" ]]; then
        append_linux_cmd "simulator=true"

        TTY4_NAME="Sim"
        TTY4_NAME_LONG="Linux host shell sim"
    fi

    if [[ "$OPT_ENABLE_DEV_MODE" = "1" ]]; then
        append_linux_cmd "__development=true"

        TTY4_NAME="Host"
        TTY4_NAME_LONG="Linux host shell dev"
    fi

    if [[ "$OPT_DOCKER_FEATURE" = "1" ]]; then
        append_linux_cmd "__docker=true"

        #
        # No calvados support. Enable host though for debugging.
        #
        OPT_ENABLE_SER_3_4=1
    fi

    if [[ "$OPT_ENABLE_FABRIC_NIC" = "1" ]]; then
        append_linux_cmd "__fabric_nic=true"
    fi
#endif

    if [[ "$OPT_ENABLE_VGA" = "1" ]]; then
        append_linux_cmd "vga=0x317 "
    fi

    #
    # To get kernel debugs on the console
    #
    if [[ "$OPT_LOG_LEVEL" != "" ]]; then
        append_linux_cmd "loglevel=$OPT_LOG_LEVEL "
    fi

    TTY0_CMD_QEMU=${LOG_DIR}${TTY0_NAME}.cmd.sh

    TTY0_PRE_CMD=${LOG_DIR}${TTY0_NAME}.pre.telnet.sh

    TTY0_CMD=${LOG_DIR}${TTY0_NAME}.telnet.sh
    TTY1_CMD=${LOG_DIR}${TTY1_NAME}.telnet.sh
    TTY2_CMD=${LOG_DIR}${TTY2_NAME}.telnet.sh
    TTY3_CMD=${LOG_DIR}${TTY3_NAME}.telnet.sh
    TTY4_CMD=${LOG_DIR}${TTY4_NAME}.telnet.sh

    TTY0_TELNET_CMD=telnet
    TTY1_TELNET_CMD=telnet
    TTY2_TELNET_CMD=telnet
    TTY3_TELNET_CMD=telnet
    TTY4_TELNET_CMD=telnet

    if [[ "$OPT_UI_LOG" = "1" ]]; then
        TTY0_TELNET_CMD=expect.sh
        TTY1_TELNET_CMD=expect.sh
        TTY2_TELNET_CMD=expect.sh
        TTY3_TELNET_CMD=expect.sh
        TTY4_TELNET_CMD=expect.sh

        cat >${LOG_DIR}/$TTY0_TELNET_CMD <<%%
#!/usr/bin/expect -f
set timeout 20
set name [lindex \$argv 0]
set port [lindex \$argv 1]
spawn telnet \$name \$port
send "\r"
expect "\r"
interact
%%
        chmod +x ${LOG_DIR}/$TTY0_TELNET_CMD
    fi
}

post_read_options_init()
{
    #
    # MY_QEMU_PID_FILE is made by us
    #
    MY_QEMU_PID_FILE=${WORK_DIR}qemu.pid

    #
    # QEMU_PID_FILE is made by QEMU and may not be readable by a user
    #
    QEMU_PID_FILE=${WORK_DIR}qemu.main.pid

    #
    # For spawned terminal sessions
    #
    MY_TERMINALS_PID_FILE=${WORK_DIR}terminals.pid

    #
    # This process
    #
    MY_PID_FILE=${WORK_DIR}sunstone.pid

    post_read_options_init_disk_vars
    post_read_options_init_net_vars
    post_read_options_init_tty_vars

    trap "errexit" 1 2 15 ERR SIGINT SIGTERM EXIT

    #
    # Seeing too many issues with no info, so making these logs again
    #
    log  "Work dir: $WORK_DIR"
    log  "Logs    : $LOG_DIR"
    log  "UUID    : $UUID"
}

#
# Clean up any user options, checking for possible errors
#
post_read_options_fini_check_tap_names()
{
    if [[ "$OPT_CLEAN" != "" ]]; then
        #
        # Force a clean
        #
        OPT_FORCE=1

        log "Clean only"
        cleanup_at_start_forced

        exit 0
    fi

    #
    # Clean up previous instance if there is one running
    #
    cleanup_at_start
}

post_read_options_fini_check_terminal()
{
    #
    # Logging only, no terminals launched
    #
    if [[ "$OPT_UI_LOG" -eq 1 ]]; then
        return
    fi

    #
    # Not needed to check this for running in the background
    #
    if [[ "$OPT_RUN_IN_BG" != "" ]]; then
        if [[ "$OPT_UI_SCREEN" = 0          && \
              "$OPT_UI_GNOME_TERMINAL" = 0  && \
              "$OPT_UI_KONSOLE" = 0         && \
              "$OPT_UI_MRXVT" = 0           && \
              "$OPT_UI_XTERM" = 0           && \
              "$OPT_UI_TMUX" = 0            ]]; then
            return
        fi
    fi

    if [[ "$OPT_UI_NO_TERM" -eq 1 ]]; then
        return
    fi

    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    log_debug "Checking terminal type is installed"

    MRXVT=`which mrxvt 2>/dev/null`

#ifdef CISCO
    local USER_PATHS=/auto/edatools/oicad/tools/vxr_user/vxr_latest/mrxvt-05b/bin/mrxvt
#endif

    for i in $MRXVT $USER_PATHS
    do
        if [[ -x $i ]]; then
            log_debug " Found $i"
            MRXVT=$i
            break
        fi
    done

    if [[ "$OPT_UI_GNOME_TERMINAL" != 0 ]]; then
        which gnome-terminal &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use gnome-terminal as terminal, not found"
            install_package_help gnome-terminal binary gnome-terminal
            OPT_UI_GNOME_TERMINAL=1
            which gnome-terminal &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_GNOME_TERMINAL=0
            fi
        else
            log_debug " Found gnome-terminal"
        fi
    fi

    if [[ "$OPT_UI_KONSOLE" != 0 ]]; then
        which konsole &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use konsole as terminal, not found"
            install_package_help konsole binary konsole

            which konsole &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_KONSOLE=0
            fi
        else
            log_debug " Found konsole"
        fi
    fi

    if [[ "$OPT_UI_MRXVT" != 0 ]]; then
        which $MRXVT &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use mrxvt as terminal, not found"
            install_package_help mrxvt binary mrxvt

            which $MRXVT &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_MRXVT=0
            fi
        else
            log_debug " Found mrxvt"
        fi
    fi

    if [[ "$OPT_UI_XTERM" != 0 ]]; then
        which xterm &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use xterm as terminal, not found"
            install_package_help xterm binary xterm

            which xterm &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_XTERM=0
            fi
        else
            log_debug " Found xterm"
        fi
    fi

    if [[ "$OPT_UI_TMUX" != 0 ]]; then
        which tmux &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use tmux as terminal, not found"
            install_package_help tmux binary tmux

            which tmux &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_TMUX=0
            fi
        else
            log_debug " Found tmux"
        fi
    fi

    if [[ "$OPT_UI_SCREEN" != 0 ]]; then
        which screen &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not use screen as terminal, not found"
            install_package_help screen binary screen

            which screen &>/dev/null
            if [[ $? -ne 0 ]]; then
                OPT_UI_SCREEN=0
            fi
        else
            log_debug " Found screen"
        fi

        if [[ ! -f ~/.screenrc ]]; then
            cat >~/.screenrc <<%%
escape ^Gg
shell -${SHELL}
#
# Quiet
#
startup_message off
#
# Auto launch
#
altscreen on
#
# Undo screen split (S)
#
bind o only
#
# Copy mode - editor in your shell!
#
bind c copy
#
# New window
#
bind n screen
#
# Prev/next screen
#
bind h prev
bind l next
#
# Up down in split screen
#
bind j focus down
bind k focus up
bind q quit
#
# Bold as GREEN
#
attrcolor b "G"
#
# Allow xterm renaming to work
#
termcapinfo xterm*|rxvt*|kterm*|Eterm* 'hs:ts=\E]0;:fs=\007:ds=\E]0;\007'
hardstatus alwayslastline "%{= g} %{= w}%-w%{=r}%n* %t%{-}%+W"

defhstatus "screen ^E (^Et) | $USER@^EH"
hardstatus off
#
# To allow scrolling on gnome-terinal
#
termcapinfo xterm ti@:te@
screen -t shell       0       bash -ls
screen -t shell       1       bash -ls
%%

            cat <<%%
###############################################################################
#
# You had no ~/.screenrc and want to use screen. I have created a sample
# file for you. To run this script however with screen, please run 'screen' and
# then re-run this script. This will allow screen to open new tabs within your
# screen session.
#
# To use screen:
#
#     To move to tab number N:           press "ctrl-g <N>"
#     To move to the tab on the right:   press "ctrl-g l"
#     To move to the tab on the left:    press "ctrl-g h"
#     To close a tab                     press "ctrl-g K"
#
###############################################################################
%%
            die "Please run screen and then retry."
        else
            log_debug " Found .screenrc"
        fi

        if [[ "$STY" = "" ]]; then
            die "STY is null. Please run screen first and then retry."
        fi
    fi

    #
    # Make sure at least one terminal is enabled
    #
    if [[ "$OPT_UI_SCREEN" = 0           && \
          "$OPT_UI_GNOME_TERMINAL" = 0   && \
          "$OPT_UI_KONSOLE" = 0          && \
          "$OPT_UI_MRXVT" = 0            && \
          "$OPT_UI_XTERM" = 0            && \
          "$OPT_UI_TMUX" = 0             ]]; then
        #
        # Highest priority, most likely to work.
        #
        while true
        do
            which $MRXVT &>/dev/null
            if [[ $? -eq 0 ]]; then
                log_debug " Chose mrxvt as default terminal"
                OPT_UI_MRXVT=1
                break
            fi

            which gnome-terminal &>/dev/null
            if [[ $? -eq 0 ]]; then
                log_debug " Chose gnome-terminal as default terminal"
                OPT_UI_GNOME_TERMINAL=1
                break
            fi

            which konsole &>/dev/null
            if [[ $? -eq 0 ]]; then
                log_debug " Chose konsole as default terminal"
                OPT_UI_KONSOLE=1
                break
            fi

            which xterm &>/dev/null
            if [[ $? -eq 0 ]]; then
                log_debug " Chose xterm as default terminal"
                OPT_UI_XTERM=1
                break
            fi

            which tmux &>/dev/null
            if [[ $? -eq 0 ]]; then
                log_debug " Chose tmux as default terminal"
                OPT_UI_TMUX=1
                break
            fi

            #
            # Let's not use screen as the default. It confuses the heck
            # out of people
            #
    #        which screen &>/dev/null
    #        if [[ $? -eq 0 ]]; then
    #            log_debug " Chose screen as default terminal"
    #            OPT_UI_SCREEN=1
    #            break
    #        fi

            err "Cannot find any graphical terminal to use."
            install_package_help gnome-terminal binary gnome-terminal
            post_read_options_fini_check_terminal
            break
        done
    fi

    #
    # Try and check the Xserver is accessible
    #
    if [[ "$OPT_UI_GNOME_TERMINAL" = 1   || \
          "$OPT_UI_KONSOLE" = 1          || \
          "$OPT_UI_MRXVT" = 1            || \
          "$OPT_UI_XTERM" = 1            ]]; then

        xlsclients
        if [[ $? -ne 0 ]]; then
            err "Cannot connect to the Xserver, DISPLAY=$DISPLAY"
            err "try 'ssh -X' to login to your server or run a vncserver/client"
            err "You can install a vnc server with 'apt-get vnc4server'"
            err "Will try to continue, but no windows may appear..."
            sleep 10
        fi
    fi
}

#
# Add support for vhost net (virtio in kernel)
#
add_qemu_and_vhost_net()
{
    VIRSH_DATA_NIC_OPTS="name='qemu'"
    if [[ $NIC_DATA_INTERFACE == "vhost-net" ]]; then
        grep -q VHOST_NET_ENABLED=0 /etc/default/qemu-kvm
        if [[ $? -eq 0 ]]; then
            banner "Please edit /etc/default/qemu-kvm and set VHOST_NET_ENABLED=1, then restart qemu-kvm"
        fi

        if [[ -c /dev/vhost-net ]]; then
            QEMU_OPT_NETDEV_DATA_NIC="${QEMU_OPT_NETDEV_DATA_NIC}vhost=on,"
        else
            die "vhost-net not enabled"
        fi

        NIC_DATA_INTERFACE=virtio-net-pci
        VIRSH_DATA_NIC_OPTS="name='vhost'"
    fi

    VIRSH_OPT_HOST_NIC="name='qemu'"
    if [[ $NIC_HOST_INTERFACE == "vhost-net" ]]; then
        grep -q VHOST_NET_ENABLED=0 /etc/default/qemu-kvm
        if [[ $? -eq 0 ]]; then
            banner "Please edit /etc/default/qemu-kvm and set VHOST_NET_ENABLED=1, then restart qemu-kvm"
        fi

        if [[ -c /dev/vhost-net ]]; then
            QEMU_OPT_NETDEV_HOST_NIC="${QEMU_OPT_NETDEV_HOST_NIC}vhost=on,"
        else
            die "vhost-net not enabled"
        fi

        NIC_HOST_INTERFACE=virtio-net-pci
        VIRSH_OPT_HOST_NIC="name='vhost'"
    fi
}

#
# Add support for checksum offload
#
add_qemu_and_csum_offload()
{
    #
    # Disable checksum offloading?
    #

    #
    # Only applicable to virtio and vhost net
    #
    case $NIC_DATA_INTERFACE in
    *virtio*)
        if [[ $NIC_DATA_CSUM_OFFLOAD_ENABLE = 0 ]]; then
            QEMU_OPT_DATA_NIC="$QEMU_OPT_DATA_NIC,csum=off,guest_csum=off"

            VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS="$VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS csum='off'"
            VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS="$VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS csum='off'"

        elif [[ $NIC_DATA_CSUM_OFFLOAD_ENABLE = 2 ]]; then
            QEMU_OPT_DATA_NIC="$QEMU_OPT_DATA_NIC,csum=on,guest_csum=on"

            VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS="$VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS csum='on'"
            VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS="$VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS csum='on'"
        fi
    ;;
    *e1000*)
    ;;
    esac

    case $NIC_HOST_INTERFACE in
    *virtio*)
        if [[ $NIC_HOST_CSUM_OFFLOAD_ENABLE = 0 ]]; then
            QEMU_OPT_HOST_NIC="$QEMU_OPT_HOST_NIC,csum=off,guest_csum=off"

            VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS="$VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS csum='off'"
            VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS="$VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS csum='off'"

        elif [[ $NIC_HOST_CSUM_OFFLOAD_ENABLE = 2 ]]; then
            QEMU_OPT_HOST_NIC="$QEMU_OPT_HOST_NIC,csum=on,guest_csum=on"

            VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS="$VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS csum='on'"
            VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS="$VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS csum='on'"
        fi
    ;;
    *e1000*)
    ;;
    esac
}

#
# Add support for virtio and vhost queues
#
add_qemu_and_queues()
{
    #
    # Only applicable to virtio and vhost net
    #
    case $NIC_DATA_INTERFACE in
    *vhost*|*virtio*)
        if [[ "$OPT_DATA_NIC_QUEUES" != "" ]]; then
            QEMU_OPT_NETDEV_DATA_NIC="${QEMU_OPT_NETDEV_DATA_NIC}queues=$OPT_DATA_NIC_QUEUES,"
            VIRSH_OPT_DATA_NIC="$VIRSH_OPT_DATA_NIC queues=\"$OPT_DATA_NIC_QUEUES\""
        fi
    ;;
    *)
        if [[ "$OPT_DATA_NIC_QUEUES" != "" ]]; then
            die "Multiqueue not supported for $NIC_DATA_INTERFACE"
        fi
    ;;
    esac

    case $NIC_HOST_INTERFACE in
    *vhost*|*virtio*)
        if [[ "$OPT_HOST_NIC_QUEUES" != "" ]]; then
            QEMU_OPT_NETDEV_HOST_NIC="${QEMU_OPT_NETDEV_HOST_NIC}queues=$OPT_HOST_NIC_QUEUES,"
            VIRSH_OPT_HOST_NIC="$VIRSH_OPT_HOST_NIC queues=\"$OPT_HOST_NIC_QUEUES\""
        fi
    ;;
    *e1000*)
        if [[ "$OPT_HOST_NIC_QUEUES" != "" ]]; then
            die "Multiqueue not supported for $NIC_HOST_INTERFACE"
        fi
    ;;
    esac
}

post_read_options_apply_qemu_network_options()
{
    # Exporting images with no kvm, do not need networking
    if [[ "$EXPORTING_NO_KVM" != "" ]]; then
        return
    fi

    if [[ "$OPT_ENABLE_NETWORK" = "0" ]]; then
        return
    fi

    get_next_mac_addresses

    add_qemu_and_vhost_net
    add_qemu_and_queues
    add_qemu_and_csum_offload

    if [[ "$OPT_ENABLE_TAPS" = "1" ]]; then
        for i in $(seq 1 $OPT_HOST_NICS)
        do
            add_qemu_cmd "-netdev tap,${QEMU_OPT_NETDEV_HOST_NIC}id=host$i,ifname=${TAP_HOST_ETH[$i]},script=no,downscript=no "
        done

        for i in $(seq 1 $OPT_HOST_NICS)
        do
            add_qemu_cmd "-device ${NIC_HOST_INTERFACE},romfile=,netdev=host$i,id=host$i,bus=pci.0,mac=${MAC_HOST_ETH[$i]}${QEMU_OPT_HOST_NIC} "
        done

        for i in $(seq 1 $OPT_DATA_NICS)
        do
            add_qemu_cmd "-netdev tap,${QEMU_OPT_NETDEV_DATA_NIC}id=data$i,ifname=${TAP_DATA_ETH[$i]},script=no,downscript=no "
        done

        # Figure out what bus to assign for virtual interfaces.
        # Normally these are on the default bus "pci.0". But a bus can only support
        # 32 devices, and we need to support more. (Also, there are other non-network
        # devices on the default bus, so it can't support 32 virtual interfaces.)
        #
        # We assign the virtual devices according to the following rules:
        # If there are <= 16 virtual interfaces, they go on the default bus.
        # If there are more than 16 virtual interfaces, assign them all to pxb bridges.
        # A pxb can support up to 32 devices. We actually put fewer than that on each 
        # pxb in case the user wants to assign physical devices to them as well.
        # If the number of pxbs has not been specified (via -pxb or -numa-pxb), 
        # we automatically compute how many pxb are needed and create them.
        # Note there appears to be a limit of 8 pxbs.

        local required_pxbs
        local bridgenum
        local default_bus_thresh=16
        local virtual_ports_per_pxb=26

        # put up to N virtual devices on each pci bridge
        required_pxbs=$(( ($OPT_DATA_NICS / $virtual_ports_per_pxb) + 1 ))

        # If there are a small number of virtual interfaces, keep them on the default bus.
        # But if VIRTSPEED is set, then always use a separate pxb, because the pxb bus number
        # determines the speed.
        if [[ ( $OPT_DATA_NICS -le $default_bus_thresh ) && ( $VIRTSPEED == "" ) ]]; then
            required_pxbs=0
        fi

        if [[ $NUM_PXBS = "" ]]; then
            # No -pxb or -numa-pxb option specified, auto-create the bridges
            add_numa_pxb "$required_pxbs" 0
        elif [[ $NUM_PXBS -lt $required_pxbs ]]; then
            err "Not enough pci bridges defined for data nics. $NUM_PXBS pxb defined but need $required_pxbs"
            exit 1
        fi

        for i in $(seq 1 $OPT_DATA_NICS)
        do
            # Set the bus for the virtual interface
            if [[ $required_pxbs -eq 0 ]]; then
                BUS="pci.0"
            else
                bridgenum=$(( ( ( $i - 1) / $virtual_ports_per_pxb) ))
                BUS="pxb_bridge$bridgenum"
            fi
            add_qemu_cmd "-device ${NIC_DATA_INTERFACE},romfile=,netdev=data$i,id=data$i,bus=${BUS},mac=${MAC_DATA_ETH[$i]}${QEMU_OPT_DATA_NIC} "
        done
    else
        #
        # No NICS enabled, for testing only
        #
        for i in $(seq 1 $OPT_HOST_NICS)
        do
            add_qemu_cmd "-device ${NIC_HOST_INTERFACE},romfile=,id=host$i,mac=${MAC_HOST_ETH[$i]} "
        done

        for i in $(seq 1 $OPT_DATA_NICS)
        do
            add_qemu_cmd "-device ${NIC_DATA_INTERFACE},romfile=,id=data$i,mac=${MAC_DATA_ETH[$i]} "
        done
    fi
}

#
# Light weight check to see if kvm acceleration is installed on the server
#
check_kvm_accel_light()
{
    kvm_ok
    if [[ $? -eq 0 ]]; then
        return 0
    fi
    return 1
}

qemu_check_version()
{
    case "$QEMU_VERSION" in
        *version\ 0.12.1*)
            banner "Your QEMU version is too old"
            log ""
            err "We support:"
            err "    >= Red Hat Enterprise Linux 7"
            err "    >= Ubuntu 14.04.03 LTS"
#ifdef CISCO
            err "    >= Centos 6.5 (only with VXR2 qemu)"
            err "    >= Centos 6.6 (only with VXR2 qemu)"
#endif
            err "    >= Centos 7.1"
            log ""
            banner "Your QEMU version is too old"

#ifdef CISCO
            if [[ "$OPT_USER_KVM_EXEC" = "" && "$EXTRA_KVM_EXEC" == "" ]]; then
                local vxr_setup=/auto/edatools/oicad/tools/vxr2_user/vxr2_480/setup.sh

                if [[ -f $vxr_setup ]]; then
                    log ""
                    log "Trying VXR2 QEMU:"
                    log "source $vxr_setup"
                    . $vxr_setup
                    log "$LD_LIBRARY_PATH"
                    log "$VXR_REL"
                    log ""
                    KVM_EXEC="$VXR_REL/bin/qemu-x86_64"
                    log "Will use VXR2 QEMU: $KVM_EXEC"

                    log ""
                    log "Or try VXR2"
                    log "http://wikicentral.cisco.com/display/PROJECT/Launching+Sunstone+with+VXR+2.0+Orchestration"
                    log ""

                    log "QEMU version installed:"
                    QEMU_VERSION=`$KVM_EXEC --version`
                    log " $QEMU_VERSION"
                else
                    log ""
                    log "Try mounting /auto/edatools on your host so I can access:"
                    log "  /auto/edatools/oicad/tools/vxr2_user/vxr2_480/setup.sh"
                    log "to use the VXR2 version of QEMU"
                    log ""
                    log "See this link for more info:"
                    log "http://wikicentral.cisco.com/display/PROJECT/Launching+Sunstone+with+VXR+2.0+Orchestration"
                    log ""
                fi
            fi
#endif
            sleep 10
            ;;

        *version\ 1.[0123]*)
            log_debug "QEMU version < 1.4"
            ;;

        *version\ 1.[456789]*)
            log_debug "QEMU version >= 1.4"
            ;;

        *version\ 2.*)
            log_debug "QEMU version >= 2.0"
            ;;
    esac
}

add_qemu_version_specific_cmds()
{
    case "$QEMU_VERSION" in
        *version\ 0.)
            log_debug "QEMU version < 1.0 tweaks"

            OPT_DISABLE_VGA="-nographic"
            ;;

        *version\ 1.[0123]*)
            log_debug "QEMU version < 1.4 tweaks"
            OPT_DISABLE_VGA="-nographic"
            ;;

        *version\ 1.[456789]*)
            log_debug "QEMU version >= 1.4 tweaks"
            OPT_DISABLE_VGA="-display none"
            ;;

        *version\ 2.*)
            log_debug "QEMU version >= 2.0 tweaks"
            OPT_DISABLE_VGA="-display none"
            if [[ "$OPT_NUMA_RED_HAT" = "" ]]; then
                sudo_check_trace sysctl kernel.numa_balancing=0
            fi
            ;;
    esac
}

post_read_options_apply_qemu_options()
{
    if [[ "$OPT_INSTALL_MEMORY_MB" != "" ]]; then
        add_qemu_cmd "-m $OPT_INSTALL_MEMORY_MB"
    else
        add_qemu_cmd "-m $OPT_PLATFORM_MEMORY_MB"
    fi

    if [[ $OPT_ENABLE_SMP -eq 1 ]]; then
        add_qemu_cmd "$OPT_PLATFORM_SMP"
    fi

    if [[ $OPT_BIOS != "" ]]; then
        add_qemu_cmd "-bios $OPT_BIOS"
    fi

    if [[ $OPT_ENABLE_KVM -eq 1 ]]; then
        add_qemu_cmd "-enable-kvm"
    else
        add_qemu_cmd "-no-kvm"
    fi

    if [[ $OPT_ENABLE_DAEMONIZE -eq 1 ]]; then
        add_qemu_cmd "-daemonize"
    fi

    add_qemu_version_specific_cmds

    if [[ $is_redhat7 -eq 1 && $OPT_ENABLE_KVM -ne 1 ]]; then
        # CEL/RHEL7 with no KVM support won't power on VM without this
        add_qemu_cmd "-no-acpi"
    fi

    if [[ "$OPT_ENABLE_VGA" = "1" ]]; then
        #
        # Would like to use SDL but it is buggy in QEMU 1.0
        #
        if [[ "$OPT_VNC_SERVER" != "" ]]; then
            add_qemu_cmd "-vnc $OPT_VNC_SERVER"
        else
            add_qemu_cmd "-vnc :0"
        fi

        add_qemu_cmd "-vga std"
    else
        add_qemu_cmd "$OPT_DISABLE_VGA"
    fi

    add_qemu_cmd "-rtc base=utc"

    add_qemu_cmd "-name $PLATFORM_NAME:$OPT_NET_NAME"

    if [[ "$OPT_ENABLE_EXIT_ON_QEMU_REBOOT" = "1" ]]; then
        add_qemu_cmd "-no-reboot"
    fi

    if [[ $OPT_ENABLE_RUNAS -eq 1 ]]; then
        if [[ "$OPT_RUNAS" != "" ]]; then
            add_qemu_cmd "-runas $OPT_RUNAS"
        else
            if [[ "$LOGNAME" != "root" ]]; then
                add_qemu_cmd "-runas $LOGNAME"
            fi
        fi
    fi

    post_read_options_apply_qemu_network_options
}

post_read_options_fini_check_should_qemu_start()
{
    #
    # Default to a need to launch QEMU
    #
    QEMU_SHOULD_START=1

    if [[ "$OPT_DISABLE_BOOT" != "" ]]; then
        QEMU_SHOULD_START=
        return
    fi

    #
    # Check if we want to launch QEMU
    #
    if [[ "$OPT_EXPORT_IMAGES" != "" ]]; then
        #
        # We have an existing disk image and can export without needing to boot
        #

        # Exported images should not be in development mode
        # OPT_ENABLE_DEV_MODE=0

        if [[ -f "$DISK1" ]]; then
            if [[ "$OPT_ENABLE_RECREATE_DISKS" = "" ]]; then
                log "QEMU launch not needed for export"
                log_low " Use -r to force recreate of disks"
                QEMU_SHOULD_START=
                return
            else
                log "Will recreate disk image for VMDK creation"
            fi
        fi
    fi
}

#
# Last check of any user options, checking for possible errors
#
post_read_options_fini()
{
    post_read_options_fini_check_should_qemu_start

    post_read_options_fini_check_tap_names

    post_read_options_fini_check_terminal

    post_read_options_platform_defaults

    if [[ "$OPT_TECH_SUPPORT" != "" ]]; then
        tech_support
        exit 0
    fi
}

check_redhat_family_install_is_ok()
{
    if [[ "$is_redhat_family" = "" ]]; then
        return
    fi

    log "Checking redhat tools are installed"

    local EXIT=

    for f in `which brctl 2>/dev/null`                  \
             `which ifconfig 2>/dev/null`
    do
        if [[ ! -f "$f" ]]; then
            err "$f not found."
            EXIT=1
            continue
        fi

        if [[ ! -u $f ]]; then
            if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
                log_debug " Found $f, setuid not set"
                continue
            fi

            trace chmod +s $f
            if [[ $? -eq 0 ]]; then
                if [[ "$EXIT" = "" ]]; then
                    warn "Failed to chmod +s $f. Please run the following as root:"
                    echo chmod +s $f
                fi
            fi

            if [[ ! -u $f ]]; then
                if [[ "$EXIT" = "" ]]; then
                    warn "Failed to suid $f. Please run the following as root:"
                    echo chmod +s $f
                fi
            fi
        else
            log_debug " Found $f, setuid set"
        fi
    done

    if [[ "$EXIT" != "" ]]; then
        exit 1
    fi

    #
    # If KVM runs under a different ID, we need to allow access
    #
    log "Changing exec perm of local dir for qemu access"
    trace chmod +x `pwd`

    true
}

#
# Check if the user can run sudo
#
can_i_run_sudo()
{
    local CAN_I_RUN_SUDO=$(sudo -n uptime 2>&1 | grep "load" | wc -l)

    if [[ ${CAN_I_RUN_SUDO} -gt 0 ]]; then
        log_debug "I can run the sudo command"
    else
        if [[ ${OPT_ENABLE_SUDO} -gt 0 ]]; then
            warn "I can't run the sudo command"
            OPT_ENABLE_SUDO=0
        fi

        SUDO=
    fi
}

check_sudo_access()
{
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    can_i_run_sudo

    if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
        return
    fi

    log_debug "Checking for sudo access"

    sudo -n grep "$LOGNAME.*NOPASSWD" /etc/sudoers &>/dev/null
    if [[ $? -ne 0 ]]; then
        log "I need to add you to /etc/sudoers"

        su -c "cat <<EOF >> /etc/sudoers
$LOGNAME ALL=(ALL:ALL) ALL
$LOGNAME ALL=(ALL) NOPASSWD:ALL
EOF"

        echo $LOGNAME ALL=NOPASSWD: ALL | sudo tee -a /etc/sudoers
        if [[ $? -ne 0 ]]; then
            err "Failed to add $LOGNAME to sudoers to avoid password entry"
        fi

        sudo grep "$LOGNAME.*NOPASSWD" /etc/sudoers
        if [[ $? -ne 0 ]]; then
            err "Failed to find $LOGNAME in /etc/sudoers. Struggling on."
        fi
    else
        log_debug " Found"
    fi
}

check_kvm_accel()
{
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    if [[ $OPT_ENABLE_KVM -eq 0 ]]; then
        return
    fi

    log_debug "Checking for KVM acceleration"

    which kvm-ok &>/dev/null
    if [[ $? -eq 0 ]]; then
        kvm-ok &>/dev/null
    else
        kvm_ok &>/dev/null
    fi

    if [[ $? != 0 ]]; then
        banner "You need KVM acceleration support on this host"

        which kvm-ok &>/dev/null
        if [[ $? -eq 0 ]]; then
            kvm-ok
        else
            kvm_ok
        fi

        exit 1
    fi

    log_debug " Found"
}

#
# Check if we have  need to check if virbr0 is in use. 0 on success.
#
check_virbr0_in_use()
{
    for i in $(seq 1 $OPT_HOST_NICS)
    do
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" ]]; then
            return 0
        fi
    done

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        BRIDGE=${BRIDGE_DATA_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" ]]; then
            return 0
        fi
    done

    return 1
}

#
# /usr/bin/script, which is used in this script to launch X-Windows, relies on
# the environemnt variable SHELL to perform normally. Therefore, we need to
# check if $SHELL is porperly set.
#
check_shell_is_ok()
{
    if [[ "$SHELL" != "" ]]; then
        if [[ ! -x $SHELL ]]; then
            die "Wrong Environment Variable SHELL Setting: $SHELL. Please correct it and try again."
        fi
    else
        die "No Environment Variable SEHLL. Please properly set it and try again."
    fi
}

check_host_bridge_is_ok()
{
    if [[ "$OPT_ENABLE_BRIDGES" = "0" ]]; then
        return
    fi

    if [[ "$OPT_ENABLE_TAPS" = "0" ]]; then
        return
    fi

    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    local EXIT=

    check_virbr0_in_use
    if [[ $? -ne 0 ]]; then
        log "host bridge (virbr0) support, not needed"
        return
    fi

    log_debug "Checking for host bridge (virbr0) support"

    ifconfig virbr0 &>/dev/null
    if [[ $? -eq 0 ]]; then
        log_debug " Found"

        return
    fi

    err "Not found. virbr0 is needed for host connectivity from VM"
    install_package_help libvirt-bin package virbr0

    ifconfig virbr0 &>/dev/null
    if [[ $? -eq 0 ]]; then
        return
    fi

    err "Lack of virbr0 will prevent the device from learning an IP address via DHCP; i.e. host connectivity will be impacted. Will continue anyway."

    if [[ "$OPT_FORCE" = "" ]]; then
        sleep 5
    fi
}

find_qemu_install()
{
    local EXIT=

    for i in \
             $OPT_USER_KVM_EXEC                             \
             /usr/libexec/qemu-kvm                          \
             /usr/libexec/kvm                               \
             /usr/bin/kvm                                   \
             /usr/bin/kvm.real                              \
             /usr/local/bin/qemu-system-x86_64              \
             /usr/bin/qemu-system-x86_64                    \
             $EXTRA_KVM_EXEC                                \
             `which qemu-kvm &>/dev/null`                   \
             `which kvm &>/dev/null`                        \
             `which qemu-system-x86_64 &>/dev/null`
    do
        if [[ -x $i ]]; then
            if [[ -u $i ]]; then
                log_low " Found $i, setuid set"
                KVM_EXEC="$i"
                EXIT=
                break
            else
                if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
                    log_low " Found $i, setuid not set"
                    KVM_EXEC="$i"
                    EXIT=
                    break
                fi

                #
                # Enable run-as-root on qemu for centos where sudo is not used
                # often
                #
                chmod +s $i &>/dev/null

                if [[ -u $i ]]; then
                    KVM_EXEC="$i"
                    log_low " Found $KVM_EXEC, setuid set"
                    EXIT=
                    break
                else
                    if [[ "$is_ubuntu" != "" ]]; then
                        log_low " Found $i, need sudo"
                        KVM_EXEC="sudo $i"
                        EXIT=
                        break
                    elif [[ "${is_redhat_family}" != "" ]]; then
                        KVM_EXEC="$i"
                        if [[ "$EXIT" = "" ]]; then
                            warn "Failed to suid $i. Please run the following as root (will try to continue):"
                            echo chmod +s $i
                        fi
                    else
                        KVM_EXEC="$i"
                        EXIT=
                        break
                    fi
                fi
            fi
        fi
    done

    if [[ "$EXIT" != "" ]]; then
        exit 1
    fi
}

check_qemu_install_is_ok()
{
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    log "Checking QEMU is installed"

    find_qemu_install

    if [[ "$KVM_EXEC" = "" ]]; then
        banner "Could not find KVM or QEMU to run"
        install_package_help qemu-system package qemu
        find_qemu_install
        if [[ "$KVM_EXEC" = "" ]]; then
            die "Can not proceed without KVM or QEMU"
        fi
    fi

    log "QEMU version installed:"
    QEMU_VERSION=`$KVM_EXEC --version`
    log " $QEMU_VERSION"

    qemu_check_version

    # Additional -cpu host needed for some versions of KVM
    pre_qemu_start_platform_defaults_ios_xrv_9000
    pre_qemu_start_platform_defaults_iosxrv

    check_qemu_img_install_is_ok
}

find_qemu_img_install()
{
    for i in \
        $OPT_USER_QEMU_IMG_EXEC \
        `which qemu-img 2>/dev/null` \
        $EXTRA_QEMU_IMG_EXEC
    do
        if [[ -x $i ]]; then
            QEMU_IMG_EXEC="$i"
            log_debug " Found $QEMU_IMG_EXEC"
            break
        fi
    done
}

check_qemu_img_install_is_ok()
{
    log_debug "Checking qemu-img is installed"

#ifdef CISCO
    # Set fallback option
    EXTRA_QEMU_IMG_EXEC=/auto/xrut/sw/cel-5/bin/qemu-img
#endif

    find_qemu_img_install

    if [[ "$QEMU_IMG_EXEC" = "" ]]; then
        banner "Could not find qemu-img to run"
        install_package_help qemu-img binary qemu-img
        find_qemu_img_install
        if [[ "$QEMU_IMG_EXEC" = "" ]]; then
            die "Can not proceed without qemu-img"
        fi
    fi
}

#
# If exporting images on a server which does not support kvm acceleration
# - need to set up some running options to make it work
#
check_export_no_kvm()
{
    if [[ "$OPT_EXPORT_IMAGES" = "" ]]; then
        return
    fi

    # Check to see if we need to dummy out kvm to be able
    # to run on servers with no KVM
    check_kvm_accel_light
    if [[ ! $? -eq 0 ]]; then
        # Protect these with Cisco
#ifdef CISCO
        # Protect these with Cisco
        EXTRA_KVM_EXEC=/auto/xrut/sw/cel-5/bin/qemu-system-x86_64
#endif
        EXPORTING_NO_KVM=1
        log "Exporting images on a server with no KVM support"
        append_linux_cmd    "no_timer_check"
        remove_linux_cmd "quiet"
        remove_linux_cmd "bigphysarea=10M"
        OPT_ENABLE_TAPS=0
        OPT_ENABLE_BRIDGES=0
        OPT_ENABLE_KVM=0
        OPT_ENABLE_SUDO=0
        OPT_ENABLE_NETWORK=0
        OPT_ENABLE_SMP=0
        OPT_ENABLE_RUNAS=0
        OPT_ENABLE_NUMA_CHECKING=0
        OPT_ENABLE_MONITOR=1
        OPT_ENABLE_EXIT_ON_QEMU_REBOOT=1
        OPT_UI_NO_TERM=1
    else
        log "Exporting images on a server with KVM support"
    fi

#ifdef CISCO
    case `hostname` in
        *-ads-*)
        log "Running on an ADS server"
        log "Disabling things we know won't work regardless of KVM enablement"
        OPT_ENABLE_TAPS=0
        OPT_ENABLE_BRIDGES=0
        OPT_ENABLE_SUDO=0
        OPT_ENABLE_NETWORK=0
        OPT_ENABLE_RUNAS=0
        ;;

        iox-ucs-*)
        log "Running on a Production Build server"
        log "Disabling things we know won't work regardless of KVM enablement"
        OPT_ENABLE_TAPS=0
        OPT_ENABLE_BRIDGES=0
        OPT_ENABLE_SUDO=0
        OPT_ENABLE_NETWORK=0
        OPT_ENABLE_RUNAS=0
        ;;
    esac
#endif
}

check_net_tools_installed()
{
    if [[ "$OPT_ENABLE_TAPS" = "0" ]]; then
        return
    fi

    log_debug "Checking networking tools are installed"

    which brctl &> /dev/null
    if [[ $? != 0 ]]; then
        install_package_help brctl binary brctl
    else
        log_debug " Found brctl"
    fi

    ip help 2>&1 | grep -q tuntap
    if [[ $? -ne 0 ]]; then
        which tunctl &> /dev/null
        if [[ $? != 0 ]]; then
            install_package_help tunctl binary tunctl
        else
            log_debug " Found tunctl"
        fi
    else
        HAVE_IP_TUNTAP=1
    fi

    which ifconfig &> /dev/null
    if [[ $? != 0 ]]; then
        install_package_help ifconfig binary ifconfig
    else
        log_debug " Found ifconfig"
    fi

    if [[ "$OPT_UI_NO_TERM" -ne 1 ]]; then
        which telnet &> /dev/null
        if [[ $? != 0 ]]; then
            install_package_help telnet binary telnet
        else
            log_debug " Found telnet"
        fi
    fi
}

#function to enable device passthrough
allow_unsafe_assigned_int_fordevicepassthru()
{
    if [[ $OPT_ENABLE_SUDO -eq 0 ]]; then
        return
    fi

    if [[ -f /sys/module/kvm/parameters/allow_unsafe_assigned_interrupts ]]; then
        $SUDO echo 1 > /sys/module/kvm/parameters/allow_unsafe_assigned_interrupts
    fi
}

create_log_dir()
{
    init_colors

    #
    # -workdir
    #
    if [[ "$OPT_WORK_DIR_HOME" != "" ]]; then
        WORK_DIR=$OPT_WORK_DIR_HOME/workdir-${OPT_NODE_NAME}/
    else
        WORK_DIR=workdir-${OPT_NODE_NAME}/
    fi

    #
    # Store logs locally and use the date to avoid losing old logs
    #
    LOG_DATE=`date "+%a_%b_%d_at_%H_%M"`
    LOG_DIR=${WORK_DIR}logs/$LOG_DATE/

    WORK_DIR=`echo $WORK_DIR | sed 's;//;/;g'`
    LOG_DIR=`echo $LOG_DIR | sed 's;//;/;g'`

    mkdir -p $WORK_DIR
    if [[ ! -d $WORK_DIR ]]; then
        die "Failed to make working dir, $WORK_DIR"
    fi

    mkdir -p $LOG_DIR
    if [[ ! -d $LOG_DIR ]]; then
        die "Failed to make log dir, $LOG_DIR in " `pwd` " " `mkdir -p $LOG_DIR`
    fi

    if [[ $? -ne 0 ]]; then
        LOG_DIR=/tmp/$LOGNAME/logs/$LOG_DATE
        mkdir -p $LOG_DIR
        if [[ $? -ne 0 ]]; then
            LOG_DIR=.
        fi
    fi

    #
    # These changes below swallow ^C on ubuntu 14 for some reason.
    # Still to figure why.
    #

    #
    # Redirect stdout into a named pipe.
    #
    # use -i to ignore signals
    #
    exec &> >(tee -i -a $LOG_DIR/$PROGRAM.console.log)
}

#
# Generate and save a unique ID for this image. We pass the UUID into the linux
# command line so it persists.
#
create_uuid()
{
    UUID_FILE=$WORK_DIR/uuid
    if [[ "$OPT_ENABLE_RECREATE_DISKS" != "" ]]; then
        /bin/rm -f $UUID_FILE
    fi

    if [[ $UUID != "" ]]; then
        return
    fi

    if [[ -f $UUID_FILE ]]; then
        UUID=$(cat $UUID_FILE)
    fi

    if [[ $UUID = "" ]]; then
        which uuidgen &>/dev/null
        UUID=$(uuidgen)
        if [[ $UUID = "" ]]; then
            UUID=$(cat /proc/sys/kernel/random/uuid)

            if [[ $? -ne 0 ]]; then
                install_package_help uuidgen util-linux uuidgen
            fi
        fi

        log_debug "Generate new UUID"
    fi

    #
    # It is preferred to use dmidecode to get the UUID
    #
    if [[ $UUID != "" ]]; then
#        append_linux_cmd "__uuid=$UUID"

        #
        # Still we want to save the UUID so we can reuse the same one again in this
        # workspace
        #
        echo $UUID > $UUID_FILE
    fi

    #
    # -machine pc-1.0 is needed to avoid the following error with dmidecode:
    #
    # dmidecode -s   system-uuid
    # SMBIOS implementations newer than version 2.6 are not
    # fully supported by this version of dmidecode.
    #
    # Actually, don't do this; as this could potentially also disable huge
    # page support. (See gigabyte_align in qemu source and the pc_compat_1_x
    # functions).
    #
    # add_qemu_cmd "-machine pc-1.0"

    local SMBIOS_SETTING="-smbios type=1,manufacturer=\\\"cisco\\\",product=\\\"$PLATFORM_NAME_WITH_SPACES\\\""

    if [[ "$OPT_SERIAL_NUMBER" != "" ]]; then
        SMBIOS_SETTING+=",serial=\\\"$OPT_SERIAL_NUMBER\\\""
    fi

    SMBIOS_SETTING+=",uuid=$UUID"

    add_qemu_cmd "$SMBIOS_SETTING"
}

brctl_delbr()
{
    local BRIDGE=$1

    if [[ "$BRIDGE" = "" ]]; then
        err "No bridge specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ ! -d /sys/devices/virtual/net/$BRIDGE ]]; then
        return
    fi

    if [[ `brctl_count_if $BRIDGE` -ne 0 ]]; then
        log "Not deleting bridge $BRIDGE, still in use:"
        brctl show $BRIDGE
        return
    fi

    log "Deleting bridge $BRIDGE"

    ifconfig_down $BRIDGE
    sudo_check_trace brctl delbr $BRIDGE

    if [[ -d /sys/devices/virtual/net/$BRIDGE ]]; then
        err "Could not delete bridge $BRIDGE"
    fi
}

brctl_delif()
{
    local BRIDGE=$1
    local TAP=$2

    if [[ "$BRIDGE" = "" ]]; then
        err "No bridge specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ "$TAP" = "" ]]; then
        err "No tap specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ "$BRIDGE" = "virbr0" || \
          "$BRIDGE" = "ztp-mgmt" ]]; then
        log "Not removing $TAP from mgmt bridge to avoid route flap."
        log "Please remove it manually if you need to."
        return
    fi

    if [[ -d /sys/devices/virtual/net/$TAP ]]; then
        #
        # Check the if is enslaved to this bridge
        #
        sudo_check_trace brctl show $BRIDGE | grep -q "\<$TAP\>"
        if [[ $? -eq 0 ]]; then
            log_debug "Deleting bridge $BRIDGE interface $TAP"

            sudo_check_trace brctl delif $BRIDGE $TAP

            sudo_check_trace brctl show $BRIDGE | grep -q "\<$TAP\>"
            if [[ $? -eq 0 ]]; then
                err "Could not remove tap $TAP from bridge $BRIDGE"
            fi
        fi
    fi
}

brctl_count_if()
{
    local BRIDGE=$1

    if [[ "$BRIDGE" = "" ]]; then
        err "No bridge specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ ! -d /sys/devices/virtual/net/$BRIDGE ]]; then
        echo 0
        return
    fi

    /bin/ls -1 /sys/devices/virtual/net/$BRIDGE/brif 2>/dev/null | wc -l
}

tunctl_add()
{
    local TAP=$1

    if [[ "$TAP" = "" ]]; then
        err "No tap specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ -d /sys/devices/virtual/net/$TAP ]]; then
        return
    fi

    TRIES=0
    while [ $TRIES -lt 3 ]
    do
        if [[ ! -d /sys/devices/virtual/net/$TAP ]]; then
            log_debug "Adding tap interface $TAP"

            if [[ $HAVE_IP_TUNTAP != "" ]]; then
                sudo_check_trace ip tuntap add $TAP mode tap
            else
                sudo_check_trace tunctl -b -u $LOGNAME -t $TAP
            fi

            if [[ -d /sys/devices/virtual/net/$TAP ]]; then
                return
            fi

            sleep 1
        fi

        TRIES=$(expr $TRIES + 1)
    done

    err "Could not add tap $TAP, tried $TRIES times."
}

tunctl_del()
{
    local TAP=$1

    if [[ "$TAP" = "" ]]; then
        err "No tap specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ ! -d /sys/devices/virtual/net/$TAP ]]; then
        return
    fi

    TRIES=0
    while [ $TRIES -lt 3 ]
    do
        if [[ -d /sys/devices/virtual/net/$TAP ]]; then
            log_debug "Deleting tap interface $TAP"

            if [[ $HAVE_IP_TUNTAP != "" ]]; then
                sudo_check_trace ip tuntap del $TAP mode tap
                if [[ "$OPT_HOST_NIC_QUEUES" != "" || $OPT_DATA_NIC_QUEUES != "" ]]; then
                    sudo_check_trace ip tuntap del $TAP mode tap multi_queue
                fi
            else
                sudo_check_trace tunctl -d $TAP
            fi

            if [[ ! -d /sys/devices/virtual/net/$TAP ]]; then
                return
            fi

            sleep 1
        fi

        TRIES=$(expr $TRIES + 1)
    done

    err "Could not remove tap $TAP, tried $TRIES times. Try running with -clean to clean up the old instance if there is one?"
}

ifconfig_down()
{
    local INTERFACE=$1

    if [[ "$INTERFACE" = "" ]]; then
        err "No interface specified in $FUNCNAME"
        backtrace
        return
    fi

    if [[ -d /sys/devices/virtual/net/$INTERFACE ]]; then
        sudo_check_trace ifconfig $INTERFACE down
    fi
}

cleanup_taps_force()
{
    I_CREATED_TAPS=

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        ifconfig_down ${TAP_DATA_ETH[$i]}
        brctl_delif ${BRIDGE_DATA_ETH[$i]} ${TAP_DATA_ETH[$i]}
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        ifconfig_down ${TAP_HOST_ETH[$i]}
        brctl_delif ${BRIDGE_HOST_ETH[$i]} ${TAP_HOST_ETH[$i]}
    done

    #
    # Assume there are other instances running we do not want to touch
    #
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        BRIDGE=${BRIDGE_DATA_ETH[$i]}
        brctl_delbr $BRIDGE
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        #
        # Avoid touching the virtual bridge as it has led to hangs in the past
        # on the host
        #
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" || \
              "$BRIDGE" = "ztp-mgmt" ]]; then
            continue
        fi

        brctl_delbr $BRIDGE
    done

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        tunctl_del ${TAP_DATA_ETH[$i]}
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        tunctl_del ${TAP_HOST_ETH[$i]}
    done
}

cleanup_taps()
{
    if [[ "$I_CREATED_TAPS" = "" ]]; then
        return
    fi

    cleanup_taps_force
}

#
# Check if the taps may be in use in another VM and if we really want to
# remove them
#
cleanup_taps_check()
{
    local CLEANUP=0

    for n in $(seq 1 $OPT_DATA_NICS)
    do
        for i in ${TAP_DATA_ETH[$n]}
        do
            if [[ -d /sys/devices/virtual/net/$i ]]; then
                ps awwwwx | grep -v grep | grep -q "\<$i\>"
                if [[ $? -eq 0 ]]; then
                    err "Tap $i is in use by:" `ps awwwwx | grep -v grep | grep "\<$i\>"`
                else
                    log "Tap $i exists but is not in use?"
                fi

                CLEANUP=1
            fi
        done
    done

    for n in $(seq 1 $OPT_HOST_NICS)
    do
        for i in ${TAP_HOST_ETH[$n]}
        do
            if [[ -d /sys/devices/virtual/net/$i ]]; then
                ps awwwwx | grep -v grep | grep -q "\<$i\>"
                if [[ $? -eq 0 ]]; then
                    err "Tap $i is in use by:" `ps awwwwx | grep -v grep | grep "\<$i\>"`
                else
                    log "Tap $i exists but is not in use?"
                fi

                CLEANUP=1
            fi
        done
    done

    if [[ "$CLEANUP" = "0" ]]; then
        return
    fi

    local CLEAN=0

    if [[ "$OPT_FORCE" = "" ]]; then
        while true; do

            cat <<%%



********************************************************************************
*                       ---- Please read carefully ----                        *
*                                                                              *
* Interfaces I am trying to use are already in use. Check that there is not    *
* an existing KVM instance using these taps.                                   *
*                                                                              *
* You can use the "-net <name>" option to use a different network name if so.  *
*                                                                              *
* Hit enter below to exit with no changes.                                     *
*                                                                              *
* Or enter yes to try to use these existing interfaces.                        *
*                                                                              *
*                       ^^^^ Please read carefully ^^^^                        *
********************************************************************************



%%

            read -p "Use existing in-use interfaces [no]?" yn
            case $yn in
                [Yy]* ) break;;
                * ) exit;;
            esac
        done

        log "Attempting to use same taps."
        CLEAN=1
    else
        log "Doing a clean before start"
        CLEAN=1
    fi

    if [[ "$CLEAN" = "1" ]]; then
        cleanup_at_start_forced
    fi
}

cleanup_my_pid_file()
{
    if [[ -s $MY_PID_FILE ]]; then
        for i in `cat $MY_PID_FILE`
        do
            #
            # No suicide
            #
            if [[ $MYPID -eq $i ]]; then
                continue
            fi

            log "Doing a forced kill of my old pid file"

            PSNAME=`ps -p $i -o comm=`
            log "Killing my pid $i $PSNAME"
            trace kill $i 2>/dev/null

            while true
            do
                ps $i &>/dev/null
                if [[ $? -eq 0 ]]; then
                    log "Waiting for PID $i to exit cleanly"
                    sleep 1
                    continue
                fi

                break
            done
        done
    fi

    rm -f $MY_PID_FILE
}

cleanup_terminal_pids()
{
    if [[ -s $MY_TERMINALS_PID_FILE ]]; then
        log "Doing a forced kill of old terminal PIDs"

        for i in `cat $MY_TERMINALS_PID_FILE`
        do
            PSNAME=`ps -p $i -o comm=`
            log_debug "Killing terminal pid $i $PSNAME"
            trace kill $i 2>/dev/null
        done
    fi

    rm -f $MY_TERMINALS_PID_FILE &>/dev/null
}

cleanup_qemu_pid()
{
    find_qemu_pid_one_shot

    #
    # Check we can read the QEMU pid file
    #
    if [[ ! -f $MY_QEMU_PID_FILE ]]; then
        return
    fi

    cat $MY_QEMU_PID_FILE &>/dev/null
    if [[ $? -ne 0 ]]; then
        log "Doing a forced kill of old QEMU PIDs"

        $SUDO cat $MY_QEMU_PID_FILE &>/dev/null
        if [[ $? -ne 0 ]]; then
            err "Could not read $MY_QEMU_PID_FILE"
            err "You may need to do:"
            err "  kill \`cat $MY_QEMU_PID_FILE\`"
            sleep 3
        fi

        for i in `$SUDO cat $MY_QEMU_PID_FILE 2>/dev/null`
        do
            PSNAME=`ps -p $i -o comm=`
            log_debug "Killing QEMU pid $i $PSNAME"
            trace kill $i 2>/dev/null
            trace $SUDO kill $i 2>/dev/null

            #
            # Give time to exit
            #
            sleep 3

            #
            # If it still exists, try harder
            #
            ps $i &>/dev/null
            if [[ $? -eq 0 ]]; then
                log "Killing -9 QEMU pid $i $PSNAME"
                trace kill -9 $i 2>/dev/null
                trace $SUDO kill -9 $i 2>/dev/null
            fi
        done
    else
        for i in `cat $MY_QEMU_PID_FILE 2>/dev/null`
        do
            PSNAME=`ps -p $i -o comm=`
            log "Killing QEMU pid $i $PSNAME"
            trace kill $i 2>/dev/null
            trace $SUDO kill $i 2>/dev/null

            #
            # Give time to exit
            #
            sleep 3

            #
            # If it still exists, try harder
            #
            ps $i &>/dev/null
            if [[ $? -eq 0 ]]; then
                PSNAME=`ps -p $i -o comm=`
                log "Killing -9 QEMU pid $i $PSNAME"
                trace kill -9 $i 2>/dev/null
            fi
        done
    fi

    rm -f $MY_QEMU_PID_FILE &>/dev/null
    $SUDO rm -f $MY_QEMU_PID_FILE &>/dev/null
}

cleanup_qemu_and_terminals_forced()
{
    # Virsh does it's own cleanup
    if [[ "$OPT_BOOT_VIRSH" != "" ]]; then
        return
    fi

    cleanup_terminal_pids

    cleanup_qemu_pid
}

cleanup_qemu_and_terminals()
{
    if [[ "$I_STARTED_VM" = "" ]]; then
        return
    fi

    I_STARTED_VM=

    cleanup_qemu_and_terminals_forced
}


tech_support_gather_()
{
    local WHAT=$1
    shift

    echo
    echo $WHAT
    echo $WHAT | sed 's/./=/g'
    echo
    echo " $*"
    $*
}

tech_support_gather()
{
    local WHAT=$1
    shift

    log_debug "+ $WHAT"

    tech_support_gather_ "$WHAT" "$*" >>$TECH_SUPPORT 2>&1
}

tech_support()
{
    #
    # Bash error code is 128 + signal, so skip tech support for ^C
    #
    if [[ "$EXIT_CODE" = "130" ]]; then
        return
    fi

    TECH_SUPPORT=$PWD/${LOG_DIR}tech-support

    log "Gathering tech support info"

    tech_support_gather "Tool version"      "echo $VERSION"
    tech_support_gather "Tool arguments"    "echo $ORIGINAL_ARGS"

    tech_support_gather "Kernel version"    "uname -a"
    tech_support_gather "Kernel cmdline"    "cat /proc/cmdline"
    uname=$(uname -r)
    tech_support_gather "Kernel flags"      "/boot/config-$uname"
    tech_support_gather "Kernel logs"       "dmesg"
    tech_support_gather "Kernel settings"   "sysctl -a"
    tech_support_gather "Ulimits"           "ulimit -a"
    tech_support_gather "QEMU version"      "$KVM_EXEC --version"
    tech_support_gather "PCI info"          "lspci"

    tech_support_gather "Disk usage"        "df ."
    tech_support_gather "Top processes"     "top -b -n 1"
    tech_support_gather "Processes"         "ps -ef"
    tech_support_gather "Free mem"          "free"
    tech_support_gather "Free mem (gig)"    "free -g"
    tech_support_gather "Virtual memory"    "vmstat"
    tech_support_gather "NUMA nodes"        "numactl -show"
    tech_support_gather "NUMA memory"       "numastat -show"
    tech_support_gather "NUMA memory"       "numastat -v"
    tech_support_gather "NUMA memory"       "numastat -m"
    #
    # Useful? slow...
    #
    # tech_support_gather "Open files"        "lsof"
    tech_support_gather "Bridged and taps"  "find /sys/devices/virtual/net"
    tech_support_gather "Route"             "route"
    tech_support_gather "Bridges"           "brctl show"
    tech_support_gather "Interfaces"        "ifconfig -a"
    tech_support_gather "Virbr0 ARP"        "arp -n -i virbr0"
    tech_support_gather "iptables"          "iptables --list"

    for i in `echo ${LOG_DIR}/*.xml`
    do
        tech_support_gather "$i" "cat $i"
    done

    for i in `echo ${LOG_DIR}/*.log`
    do
        tech_support_gather "$i" "cat $i"
    done

    #
    # If running in the background we don't log much so don't spam the
    # console
    #
    if [[ "$OPT_RUN_IN_BG" = "" ]]; then
        log "Final log files:"

        #
        # Create a local link to the latest log files and tech support
        #
        local SUFFIX=
        if [[ "$OPT_NODE_NAME" != "" ]]; then
            SUFFIX="-$OPT_NODE_NAME"
        fi

        #
        # Do not create symlinks if we did not create any logging
        #
        if [[ "$OPT_UI_LOG" -eq 1 || "$OPT_UI_NO_TERM" -ne 1 ]]; then
            if [[ "$OPT_DISABLE_LOG_SYMLINKS" = "" ]]; then
                ln -sf $LOG_DIR/$TTY0_NAME.log $TTY0_NAME${SUFFIX}.log 2>/dev/null
                ln -sf $LOG_DIR/$TTY1_NAME.log $TTY1_NAME${SUFFIX}.log 2>/dev/null
                ln -sf $LOG_DIR/$TTY2_NAME.log $TTY2_NAME${SUFFIX}.log 2>/dev/null
                ln -sf $LOG_DIR/$TTY3_NAME.log $TTY3_NAME${SUFFIX}.log 2>/dev/null
                ln -sf $LOG_DIR/$TTY4_NAME.log $TTY4_NAME${SUFFIX}.log 2>/dev/null

                ls -l $TTY0_NAME${SUFFIX}.log 2>/dev/null
                ls -l $TTY1_NAME${SUFFIX}.log 2>/dev/null
                ls -l $TTY2_NAME${SUFFIX}.log 2>/dev/null
                ls -l $TTY3_NAME${SUFFIX}.log 2>/dev/null
                ls -l $TTY4_NAME${SUFFIX}.log 2>/dev/null
            fi
        fi
    fi

    readlink -f $TECH_SUPPORT
}

cleanup_at_exit()
{
    lock_release

    if [[ "$OPT_UI_NO_TERM" -eq 1 ]]; then
        log "No terminal mode selected, leaving QEMU running"
        return
    fi

    fix_output $LOG_DIR/$TTY0_NAME.log &>/dev/null
    fix_output $LOG_DIR/$TTY1_NAME.log &>/dev/null
    fix_output $LOG_DIR/$TTY2_NAME.log &>/dev/null
    fix_output $LOG_DIR/$TTY3_NAME.log &>/dev/null
    fix_output $LOG_DIR/$TTY4_NAME.log &>/dev/null

    cleanup_qemu_and_terminals
    cleanup_taps

    # Virsh does it's own cleanup
    if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
        cleanup_my_pid_file
    fi

    if [[ ! "$OPT_EXPORT_IMAGES" = "" ]]; then
        local NAME=`echo $OVA_NAME | sed 's/\..*//g'`
        log "Exported $NAME images are:"
        log_debug "  OUTPUT_DIR=$OUTPUT_DIR"
        log_debug "  NAME=$NAME"

        ls -als $OUTPUT_DIR | grep $NAME | grep "\.qcow2" 2>&1 >  ${WORK_DIR}image_list
        ls -als $OUTPUT_DIR | grep $NAME | grep "\.ova"   2>&1 >> ${WORK_DIR}image_list
        ls -als $OUTPUT_DIR | grep $NAME | grep "\.iso"   2>&1 >> ${WORK_DIR}image_list
        ls -als $OUTPUT_DIR | grep $NAME | grep "\.xml"   2>&1 >> ${WORK_DIR}image_list

        cat ${WORK_DIR}image_list | sort -nk6

        if [[ "$OPT_BOOTSTRAP" != "" ]]; then
            if [[ -e ${OUTPUT_DIR}$OUTPUT_BOOTSTRAP_NAME ]]; then
                if [[ $OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO -eq 1 ]]; then
                    log "To use Bootstrap add to qemu: '-drive file=${OUTPUT_DIR}${OUTPUT_BOOTSTRAP_NAME},if=virtio,media=cdrom,index=3'"
                else
                    log "To use Bootstrap add to qemu: '-drive file=${OUTPUT_DIR}${OUTPUT_BOOTSTRAP_NAME},media=cdrom,index=3'"
                fi
            fi
        fi

        local XML=`basename $VIRSH_XML`
        log "Exported VIRSH XML '$XML' validated state is '$VIRSH_VALIDATED'"

        if [[ "$VIRSH_VALIDATED" = "unknown" ]]; then
            which virt-xml-validate &> /dev/null
            if [[ $? -ne 0 ]]; then
                warn "I was not able to validate this virsh XML as virt-xml-validate is not installed"
            fi
        fi
    fi
    if [[ "$CLEANUP_SRIOV" = "1" ]]; then
        sudo_check_trace modprobe -r ixgbe
#       sudo_check_trace modprobe -r igb
        sudo_check_trace modprobe -r i40gbe
    fi

}

cleanup_at_start()
{
    cleanup_my_pid_file
    cleanup_qemu_and_terminals
    cleanup_taps_check
}

cleanup_at_start_forced()
{
    cleanup_my_pid_file
    cleanup_qemu_and_terminals_forced
    cleanup_taps_force
}

commonexit()
{
    cleanup_at_exit
}

errexit()
{
    EXIT_CODE=$?

    #
    # Release the lock as soon as we can in case we fail during exit
    #
    lock_release

    #
    # Virsh cleanup up is unique
    #
    if [[ "$OPT_BOOT_VIRSH" != "" ]]; then
        okexit
        return
    fi

    if [[ $EXIT_CODE -eq 0 ]]; then
        okexit
        return
    fi

    if [[ "$EXITING" != "" ]]; then
        exit $RET
    fi

    EXITING=1

    RET=$EXIT_CODE

    err "Exiting, code $RET"

    commonexit

    #
    # Record some potentially useful info. Need to do this last as we record
    # our own output.
    #
    tech_support

    exit $RET
}

okexit()
{
    if [[ "$EXITING" != "" ]]; then
        exit 0
    fi

    EXITING=1

    # If using virsh, cleanup with virsh
    if [[ "$OPT_BOOT_VIRSH" != "" ]]; then
        log "Exiting and cleaning up virsh domain $DOMAIN_NAME"
        trace virsh reboot $DOMAIN_NAME
        trace virsh shutdown $DOMAIN_NAME
        trace virsh destroy $DOMAIN_NAME
        trace virsh list
        labyrinth 10
        commonexit
    fi

    log "Exiting..."

    if [[ "$OPT_RUN_IN_BG" != "" ]]; then
        if [[ "$I_STARTED_VM" = "" ]]; then
            log "Exiting, no instance running"
        else
            #
            # Useful to show the port info before exit
            #
            qemu_show_port_info

            if [[ "$QEMU_SHOULD_START" != "" ]]; then
                log "Exiting and leaving instance running, pid:"
                log_low " $MY_QEMU_PID_FILE"
                log_low " "`cat $MY_QEMU_PID_FILE`
            fi
        fi
        #
        # No need to do this in success cases
        #
        # tech_support &

        exit 0
    fi

    log "$PROGRAM, exiting"

    commonexit
}

get_next_ip_addresses()
{
    SUB_ADDRESS1=$(expr \( $RANDOM % 250 \))
    if [[ "$SUB_ADDRESS1" = "" ]]; then
        die "Do not run this tool with sh, call it directly."
    fi

    SUB_ADDRESS2=$(expr \( $RANDOM % 250 \))

    ADDRESS[$i]="192.${SUB_ADDRESS1}.${SUB_ADDRESS2}"
    IP_PATTERN="${ADDRESS[$i]}"
    RESULT=$(/sbin/ifconfig|egrep "inet.*${IP_PATTERN}")
    while [ -n "${RESULT}" ]
    do
        SUB_ADDRESS1=$(expr \( $RANDOM % 250 \))
        SUB_ADDRESS2=$(expr \( $RANDOM % 250 \))

        ADDRESS[$i]="192.${SUB_ADDRESS1}.${SUB_ADDRESS2}"
        IP_PATTERN="${ADDRESS[$i]}"
        RESULT=$(/sbin/ifconfig|egrep "inet.*${IP_PATTERN}")
    done

    ADDRESS[$i]="192.${SUB_ADDRESS1}.${SUB_ADDRESS2}.1"
}

get_mac_address()
{
    printf '52:46:01:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

get_next_mac_addresses()
{
    #
    # Add lots of randomness as we cannot always tell if a peer VM is booting
    # up at the same time and might land on one of our MACs. Try and make this
    # an unlikely event.
    #
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        if [[ ${MAC_DATA_ETH[$i]} = "" ]]; then
            MAC_DATA_ETH[$i]=52:46:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{8}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;' | tr '[:lower:]' '[:upper:]'`
        fi
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        if [[ ${MAC_HOST_ETH[$i]} = "" ]]; then
            MAC_HOST_ETH[$i]=52:46:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{8}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;' | tr '[:lower:]' '[:upper:]'`
        fi
    done
}

tune_taps_and_bridges()
{
    log "Tune interfaces"
    for i in $(seq 1 $OPT_HOST_NICS)
    do
        sudo_check_trace ifconfig ${TAP_HOST_ETH[$i]} txqueuelen $OPT_TXQUEUELEN
        sudo_check_trace ifconfig ${TAP_HOST_ETH[$i]} mtu $OPT_MTU
    done

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        sudo_check_trace ifconfig ${TAP_DATA_ETH[$i]} txqueuelen $OPT_TXQUEUELEN
        sudo_check_trace ifconfig ${TAP_DATA_ETH[$i]} mtu $OPT_MTU
    done

    log "Tune bridges"
    for i in $(seq 1 $OPT_HOST_NICS)
    do
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" || \
              "$BRIDGE" = "ztp-mgmt" ]]; then
            continue
        fi

        sudo_check_trace ifconfig ${BRIDGE_HOST_ETH[$i]} txqueuelen $OPT_TXQUEUELEN
        sudo_check_trace ifconfig ${BRIDGE_HOST_ETH[$i]} mtu $OPT_MTU
    done

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        BRIDGE=${BRIDGE_DATA_ETH[$i]}

        sudo_check_trace ifconfig ${BRIDGE_DATA_ETH[$i]} txqueuelen $OPT_TXQUEUELEN
        sudo_check_trace ifconfig ${BRIDGE_DATA_ETH[$i]} mtu $OPT_MTU
    done
}

#
# Currently, the default behaviour for bridges when switching fragmented
# packets is to reassemble the original packet as it passes through the
# bridge, as it is required by Netfilter for connection tracking
# purposes. This occasionally leads to unexpected behaviour, notably
# when the reassembled packet needs to be punted and exceeds the 10000
# byte limit of DPA punt/inject messages, and is therefore dropped by
# the DPA.
#
# With this disabled, fragmented packets pass transparently through the
# bridges, enabling for example pings of over 10000 bytes to work on the
# GigE interfaces.
#
# The same effect can be achieved by reducing the 10000-byte default MTU
# of the bridged interfaces, as the bridge would reassemble and then
# refragment the packets using the smaller MTU; but I think it would be
# best to just not have the bridges do any processing on fragmented
# packets in order to prevent any other surprises (this is also the
# recommendation in the libvirt documentation).
#
function platform_disable_bridge_conn_tracking
{
    log "Disabling conntracking on bridges"

    sudo_check_trace sysctl net.bridge.bridge-nf-call-arptables=0
    sudo_check_trace sysctl net.bridge.bridge-nf-call-ip6tables=0
    sudo_check_trace sysctl net.bridge.bridge-nf-call-iptables=0
    sudo_check_trace sysctl net.bridge.bridge-nf-filter-vlan-tagged=0
}

init_bridge()
{
    platform_disable_bridge_conn_tracking
}

create_bridge()
{
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    if [[ "$OPT_ENABLE_BRIDGES" = "0" ]]; then
        return
    fi

    init_bridge

    #
    # create the bridge
    #
    log "Create bridges"
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        BRIDGE=${BRIDGE_DATA_ETH[$i]}

        #
        # brctl show does not exit with failure on not found, so need to grep
        #
        brctl show | grep -q "\<$BRIDGE\>"
        if [[ $? -ne 0 ]]; then
            sudo_check_trace brctl addbr $BRIDGE
        else
            log_low " Bridge $BRIDGE already exists"
        fi
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" || \
              "$BRIDGE" = "ztp-mgmt" ]]; then
            continue
        fi

        #
        # brctl show does not exit with failure on not found, so need to grep
        #
        brctl show | grep -q "\<$BRIDGE\>"
        if [[ $? -ne 0 ]]; then
            sudo_check_trace brctl addbr $BRIDGE
        else
            log_low " Bridge $BRIDGE already exists"
        fi
    done

    #
    # bring up the bridge
    #
    log_debug "Bring up bridges"

    for i in $(seq 1 $OPT_DATA_NICS)
    do
        BRIDGE=${BRIDGE_DATA_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" || \
              "$BRIDGE" = "ztp-mgmt" ]]; then
            log_debug "XR management bridge $i using $BRIDGE, skip address assign"
            continue
        fi

        if [[ "$OPT_ENABLE_ADDRESS_ASSIGN" = "1" ]]; then
            get_next_ip_addresses
            log_debug "XR traffic bridge $i using ${ADDRESS[$i]}"
            sudo_check_trace ifconfig $BRIDGE ${ADDRESS[$i]} up
        fi

        sudo_check_trace ifconfig $BRIDGE up

        if [[ "$OPT_ENABLE_SNOOPING" = "1" ]]; then
            sudo_check_trace sh <<EOF
echo -n 1 > /sys/devices/virtual/net/$BRIDGE/bridge/multicast_snooping
EOF
        elif [[ "$OPT_ENABLE_SNOOPING" = "0" ]]; then
            sudo_check_trace sh <<EOF
echo -n 0 > /sys/devices/virtual/net/$BRIDGE/bridge/multicast_snooping
EOF
        fi

        if [[ "$OPT_ENABLE_QUERIER" = "1" ]]; then
            sudo_check_trace sh <<EOF
echo -n 1 > /sys/devices/virtual/net/$BRIDGE/bridge/multicast_querier
EOF
        elif [[ "$OPT_ENABLE_QUERIER" = "0" ]]; then
            sudo_check_trace sh <<EOF
echo -n 0 > /sys/devices/virtual/net/$BRIDGE/bridge/multicast_querier
EOF
        fi

        if [[ "$OPT_ENABLE_LLDP" = "1" ]]; then
            sudo_check_trace sh <<EOF
echo -n 16384 > /sys/devices/virtual/net/$BRIDGE/bridge/group_fwd_mask
EOF
        fi
    done

    get_next_ip_addresses

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        if [[ "$BRIDGE" = "virbr0" || \
              "$BRIDGE" = "ztp-mgmt" ]]; then
            log_debug "XR management bridge $i using $BRIDGE, skip address assign"
            continue
        fi

        if [[ "$OPT_ENABLE_ADDRESS_ASSIGN" = "1" ]]; then
            get_next_ip_addresses
            log_debug "XR management bridge $i using ${ADDRESS[$i]}"
            sudo_check_trace ifconfig $BRIDGE ${ADDRESS[$i]} up
        fi

        sudo_check_trace ifconfig $BRIDGE up
    done

    #
    # show my bridge
    #
    if [[ "$OPT_DEBUG" != "" ]]; then
        log "Show bridges"
        for i in $(seq 1 $OPT_DATA_NICS)
        do
            trace ifconfig ${BRIDGE_DATA_ETH[$i]}
            trace brctl show ${BRIDGE_DATA_ETH[$i]}
            trace brctl showmacs ${BRIDGE_DATA_ETH[$i]}
        done

        for i in $(seq 1 $OPT_HOST_NICS)
        do
            trace ifconfig ${BRIDGE_HOST_ETH[$i]}
            trace brctl show ${BRIDGE_HOST_ETH[$i]}
            trace brctl showmacs ${BRIDGE_HOST_ETH[$i]}
        done
    fi
}

create_taps()
{
    if [[ "$OPT_ENABLE_TAPS" = "0" ]]; then
        return
    fi

    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    #
    # Create the taps
    #
    if [[ "$OPT_HOST_NIC_QUEUES" != "" ]]; then
        log_debug "Create control plane multiqueue taps"

        for i in $(seq 1 $OPT_HOST_NICS)
        do
            sudo_check_trace ip tuntap add dev ${TAP_HOST_ETH[$i]} mode tap multi_queue
        done
    else
        log_debug "Create control plane taps"

        for i in $(seq 1 $OPT_HOST_NICS)
        do
            tunctl_add ${TAP_HOST_ETH[$i]}
        done
    fi

    if [[ "$OPT_DATA_NIC_QUEUES" != "" ]]; then
        log_debug "Create data plane multiqueue taps"

        for i in $(seq 1 $OPT_DATA_NICS)
        do
            sudo_check_trace ip tuntap add dev ${TAP_DATA_ETH[$i]} mode tap multi_queue
        done
    else
        log_debug "Create data plane taps"

        for i in $(seq 1 $OPT_DATA_NICS)
        do
            tunctl_add  ${TAP_DATA_ETH[$i]}
        done
    fi

    #
    # bring up the tap
    #
    log "Bring up taps"
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        sudo_check_trace ifconfig ${TAP_DATA_ETH[$i]} up
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        sudo_check_trace ifconfig ${TAP_HOST_ETH[$i]} up
    done

    #
    # show the tap
    #
    if [[ "$OPT_DEBUG" != "" ]]; then
        log "Show taps"
        for i in $(seq 1 $OPT_DATA_NICS)
        do
            trace ifconfig ${TAP_DATA_ETH[$i]}
        done

        for i in $(seq 1 $OPT_HOST_NICS)
        do
            trace ifconfig ${TAP_HOST_ETH[$i]}
        done
    fi

    #
    # attach tap interface to bridge
    #
    log "Add taps to bridges"
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        sudo_check_trace brctl addif ${BRIDGE_DATA_ETH[$i]} ${TAP_DATA_ETH[$i]}
    done

    for i in $(seq 1 $OPT_HOST_NICS)
    do
        sudo_check_trace brctl addif ${BRIDGE_HOST_ETH[$i]} ${TAP_HOST_ETH[$i]}
    done

    tune_taps_and_bridges

    I_CREATED_TAPS=1
}

init_colors()
{
    DULL=0
    FG_BLACK=30
    FG_RED=31
    FG_GREEN=32
    FG_YELLOW=33
    FG_BLUE=34
    FG_MAGENTA=35
    FG_CYAN=36
    FG_WHITE=37
    FG_NULL=00
    BG_NULL=00
    ESC="["
    RESET="${ESC}${DULL};${FG_WHITE};${BG_NULL}m"
    BLACK="${ESC}${DULL};${FG_BLACK}m"
    RED="${ESC}${DULL};${FG_RED}m"
    GREEN="${ESC}${DULL};${FG_GREEN}m"
    YELLOW="${ESC}${DULL};${FG_YELLOW}m"
    BLUE="${ESC}${DULL};${FG_BLUE}m"
    MAGENTA="${ESC}${DULL};${FG_MAGENTA}m"
    CYAN="${ESC}${DULL};${FG_CYAN}m"
    WHITE="${ESC}${DULL};${FG_WHITE}m"
}

log()
{
    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}${GREEN}$*${RESET}"
    else
        echo "`date`"": ${LOG_PREFIX}${GREEN}$*${RESET}" | tee -a $LOG_DIR/$PROGRAM.log
    fi

    if [[ $? -ne 0 ]]; then
        die "Cannot write to log file"
    fi
}

log_low()
{
    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}$*"
    else
        echo "`date`"": ${LOG_PREFIX}$*" | tee -a $LOG_DIR/$PROGRAM.log
    fi

    if [[ $? -ne 0 ]]; then
        die "Cannot write to log file"
    fi
}

log_debug()
{
    if [[ "$OPT_DEBUG" = "" ]]; then
        #
        # Still log to the log file if not the screen
        #
        if [[ "$LOG_DIR" != "" ]]; then
            echo "`date`"": ${LOG_PREFIX}$*" >> $LOG_DIR/$PROGRAM.log
        fi

        if [[ $? -ne 0 ]]; then
            die "Cannot write to log file"
        fi

        return
    fi

    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}$*"
    else
        echo "`date`"": ${LOG_PREFIX}$*" | tee -a $LOG_DIR/$PROGRAM.log
    fi

    if [[ $? -ne 0 ]]; then
        die "Cannot write to log file"
        exit 1
    fi
}

backtrace()
{
    local deptn=${#FUNCNAME[@]}

    for ((i=1; i<$deptn; i++)); do
        local func="${FUNCNAME[$i]}"
        local line="${BASH_LINENO[$((i-1))]}"
        local src="${BASH_SOURCE[$((i-1))]}"
        printf '%*s' $i '' # indent
        echo "at: $func(), $src, line $line"
    done
}

trace_top_caller()
{
    local func="${FUNCNAME[1]}"
    local line="${BASH_LINENO[0]}"
    local src="${BASH_SOURCE[0]}"
    echo "  called from: $func(), $src, line $line"
}

trace()
{
    echo "`date`"": + $*" | tee -a $LOG_DIR/$PROGRAM.log
    $* 2>&1 | tee -a $LOG_DIR/$PROGRAM.log
    return ${PIPESTATUS[0]}
}

trace_quiet()
{
    echo "`date`"": + $*" | tee -a $LOG_DIR/$PROGRAM.log

    if [[ "$OPT_DEBUG" != "" ]]; then
        $*
    else
        $* >/dev/null
    fi
}

err()
{
    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}${RED}ERROR: $*${RESET}"
    else
        echo "`date`"": ${LOG_PREFIX}${RED}ERROR: $*${RESET}" | tee -a $LOG_DIR/$PROGRAM.log
    fi
}

warn()
{
    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}${BLUE}WARNING: $*${RESET}"
    else
        echo "`date`"": ${LOG_PREFIX}${BLUE}WARNING: $*${RESET}" | tee -a $LOG_DIR/$PROGRAM.log
    fi
}

die()
{
    if [[ "$LOG_DIR" = "" ]]; then
        echo "`date`"": ${LOG_PREFIX}${RED}FATAL ERROR: $*${RESET}"
    else
        echo "`date`"": ${LOG_PREFIX}${RED}FATAL ERROR: $*${RESET}" | tee -a $LOG_DIR/$PROGRAM.log
    fi

    backtrace

    exit 1
}

banner()
{
    if [[ "$TERM" = "dumb" ]]; then
        TERM="rxvt"
        export TERM
    fi

    COLUMNS=$(tput cols 2>/dev/null)
    export COLUMNS

    if [[ "$COLUMNS" = "" ]]; then
        echo "################################################################################"
        echo " $*"
        echo "################################################################################"
        return
    fi

    echo $RED

    arg="$*"

    perl - "$arg" <<'EOF'
    my $arg=shift;
    my $width = $ENV{COLUMNS};

    if ($width > 80) {
        $width = 80;
    }

    if ($width == 0) {
        $width = 80;
    }

    my $len = length($arg);

    printf "#" x $width . "\n";
    printf "#";

    my $pad1 = int(($width - $len - 1) / 2);
    printf " " x $pad1;

    printf "$arg";

    my $pad2 = int(($width - $len - 1) / 2);
    if ($pad2 + $pad1 + 2 + $len > $width) {
        $pad2--;
    }

    printf " " x $pad2;

    printf "#\n";
    printf "#" x $width . "\n";
EOF
    echo $RESET
}

fix_output()
{
    in=$*

    if [[ ! -f "$in" ]]; then
        return
    fi

    out=$in.tmp
    cat $in | perl -pe 's/\e([^\[\]]|\[.*?[a-zA-Z]|\].*?\a)//g' | col -b > $out
    mv $out $in
}

find_random_open_port_()
{
    RANDOM_ADDRESS=

    VM_ADDRESS=`expr \( $RANDOM % $RANDOM_PORT_RANGE \) + $RANDOM_PORT_BASE`
    if [[ "$VM_ADDRESS" = "" ]]; then
        die "Do not run this tool with sh, call it directly."
    fi

    RESULT=`netstat -plano 2>/dev/null | grep $VM_ADDRESS; lsof -iTCP:$VM_ADDRESS; lsof -iUDP:$VM_ADDRESS`
    while [ "$RESULT" != "" ]
    do
        VM_ADDRESS=`expr \( $RANDOM % $RANDOM_PORT_RANGE \) + $RANDOM_PORT_BASE`
        RESULT=`netstat -plano 2>/dev/null | grep $VM_ADDRESS; lsof -iTCP:$VM_ADDRESS; lsof -iUDP:$VM_ADDRESS`
    done

    RANDOM_ADDRESS=$VM_ADDRESS

    #
    # Double check
    #
    netstat -plano 2>/dev/null | grep $VM_ADDRESS; lsof -iTCP:$VM_ADDRESS; lsof -iUDP:$VM_ADDRESS
}

#
# Need to filter not just currently open ports but also those we plan to
# use. This does not filter out other processes running at the same time.
#
find_random_open_port()
{
    local TRIES=0

    while true
    do
        find_random_open_port_

        local COLLISION=0
        for PORT in $EXISTING_PORTS
        do
            if [[ $RANDOM_ADDRESS -eq $PORT ]]; then
                COLLISION=1
                break
            fi
        done

        TRIES=$(expr $TRIES + 1)

        if [[ "$TRIES" -eq 60 ]]; then
            die "Cannot allocate a local port. Tried $TRIES times"
        fi

        if [[ $COLLISION -eq 1 ]]; then
            continue
        fi

        EXISTING_PORTS="$EXISTING_PORTS $RANDOM_ADDRESS"
        break
    done
}

create_telnet_ports()
{
    if [[ "$TTY_HOST" = "" ]]; then
        TTY_HOST="localhost"

        #
        # 0.0.0.0 listens on all local interfaces
        #
        TTY_HOST="0.0.0.0"
    fi

    if [[ "$QEMU_PORT" = "" ]]; then
        find_random_open_port
        QEMU_PORT=$RANDOM_ADDRESS
    fi

    if [[ "$TTY1_PORT" = "" ]]; then
        find_random_open_port
        TTY1_PORT=$RANDOM_ADDRESS
    fi

    if [[ "$TTY2_PORT" = "" ]]; then
        find_random_open_port
        TTY2_PORT=$RANDOM_ADDRESS
    fi

    if [[ "$TTY3_PORT" = "" ]]; then
        find_random_open_port
        TTY3_PORT=$RANDOM_ADDRESS
    fi

    if [[ "$TTY4_PORT" = "" ]]; then
        find_random_open_port
        TTY4_PORT=$RANDOM_ADDRESS
    fi
}

create_disk()
{
    local NAME=$1
    local SIZE=$2
    local TYPE=$3

    if [[ "$OPT_DISABLE_BOOT" != "" ]]; then
        log "QEMU boot disabled, skipping disk creation"
        return
    fi

    trace rm -f $NAME
    log_debug "Creating disk $NAME, size $SIZE"

    if [[ "$OPT_INSTALL_CREATE_QCOW2" != "" ]]; then
        if [[ "$QEMU_IMG_EXEC" = "" ]]; then
            check_qemu_img_install_is_ok
        fi

        trace_quiet $QEMU_IMG_EXEC create -f qcow2 -o preallocation=metadata $NAME $SIZE
        if [[ $? -ne 0 ]]; then
            die "Failed to create qcow2 disk $NAME size $SIZE"
        fi
    else
        trace_quiet dd if=/dev/zero of=$NAME bs=1 count=0 seek=$SIZE
        if [[ $? -ne 0 ]]; then
            die "Failed to create disk $NAME size $SIZE"
        fi
    fi

    if [[ "$OPT_DEBUG" != "" ]]; then
        ls -lash $NAME
    fi
}

disk_file_to_format_type()
{
    case "$*" in
        *qcow* ) 
            return
            ;;
        *vmdk* ) 
            return
            ;;
    esac
    echo "format=raw,"; 
}

add_non_boot_disks()
{
    if [[ "$OPT_DISK2" != "" ]]; then
        log "Adding $OPT_DISK2"

        local file_and_path=`full_path_name $OPT_DISK2`
        local disk_format=$(disk_file_to_format_type $file_and_path)
        add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT,index=4 "
        return
    fi
}

#
# Extract an ISO to disk one file at a time. Slow, but does not need root.
#
extract_iso()
{
    local ISO_FILE=$1
    local OUT_DIR=$2
    local DIR=
    local ERR=

    if [[ "$ISO_FILE" = "" ]]; then
        die "No ISO file"
    fi

    if [[ "$OUT_DIR" = "" ]]; then
        die "No out dir for ISO create"
    fi

    #
    # Extract the ISO contents
    #
    local TMP=`mktemp`
    if [[ ! -f $TMP ]]; then
        die "Failed to make temp file $TMP"
    fi

    log_debug "+ isoinfo -R -l -i ${ISO_FILE}";

    isoinfo -R -l -i ${ISO_FILE} > $TMP
    if [[ $? -ne 0 ]]; then
        die "Failed to extract $ISO_FILE"
    fi

    if [[ ! -f "$TMP" ]]; then
        die "Failed to make $TMP"
    fi

    while read LINE
    do
        if [[ "$OPT_DEBUG" != "" ]]; then
            echo "$LINE"
        fi

        #
        # Ignore empty lines
        #
        if [[ "$LINE" = "" ]]; then
            continue
        fi

        #
        # Look for directory lines
        #
        local DIR_PREFIX="Directory listing of "

        if [[ $LINE == "${DIR_PREFIX}"* ]]; then
            #
            # Remove the "Directory listing of " prefix
            #
            DIR=`echo $LINE | sed s/"${DIR_PREFIX}"//g`

            mkdir -p ${OUT_DIR}/$DIR
        else
            #
            # Ignore directories
            #
            if [[ $LINE = "d"* ]]; then
                continue
            fi

            #
            # Strip leading fields
            #
            local FILE=`echo $LINE | sed 's/.* //g'`

            #
            # isoinfo to leave .. as a file sometimes
            #
            if [[ "$FILE" = ".." ]]; then
                continue
            fi

            #
            # Extract the file
            #
            local DIR_FILE=${DIR}${FILE}
            local OUT_DIR_FILE=${OUT_DIR}${DIR}${FILE}

            if [[ "$OPT_DEBUG" != "" ]]; then
                log "isoinfo -R -i ${ISO_FILE} -x ${DIR_FILE}"
            fi

            isoinfo -R -i ${ISO_FILE} -x ${DIR_FILE} > ${OUT_DIR_FILE}
            if [[ $? -ne 0 ]]; then
                err "Failed to extract $DIR_FILE"
                ERR=1
            fi

            if [[ "$OPT_DEBUG" != "" ]]; then
                /bin/ls -lart ${OUT_DIR_FILE}
            fi
        fi
    done <$TMP

    echo "# Baked by $LOGNAME " `date` >> $WORK_DIR/iso/boot/grub2/grub.cfg

    plugin_enable_debugging $WORK_DIR

    /bin/rm -f $TMP

    if [[ "$ERR" != "" ]]; then
        die "Failed to extract all files"
    fi
}

#
# Modify an ISO.
#
mount_iso()
{
    which isoinfo &>/dev/null
    if [[ $? -ne 0 ]]; then
        install_package_help isoinfo binary isoinfo
        exit 0
    fi

    ISO_DIR=${WORK_DIR}iso;

    if [[ -d $ISO_DIR ]]; then
        log_debug " Remove old ISO before starting"

        trace rm -rf $ISO_DIR
        if [[ -d $ISO_DIR ]]; then
            die "Failed to remove $ISO_DIR"
        fi
    fi

    mkdir -p $ISO_DIR
    if [[ $? -ne 0 ]]; then
        die "Failed to create $ISO_DIR for mounting/modifying ISO"
    fi

    extract_iso $OPT_BOOT_ISO $ISO_DIR
}

#
# Modify the linux command line in our ISO.
#
modify_iso_linux_cmdline()
{
    local NEW_ISO=$1
    local CMDLINE_APPEND="$2"
    local CMDLINE_REMOVE="$3"
    local GRUB_APPEND="$4"
    local GRUB_REMOVE="$5"

    #
    # Warn if we cannot satisfy the flags given
    #
    if [[ $OPT_DISABLE_MODIFY_ISO != "" ]]; then
        warn "Cannot modify ISO for the following operations:"
        warn "  linux cmdline add:     $CMDLINE_APPEND"
        warn "  linux cmdline remove:  $CMDLINE_REMOVE"
        warn "  grub add:              $GRUB_APPEND"
        warn "  grub remove:           $GRUB_REMOVE"
        return
    fi

    log "Modifying ISO..."
    log_debug " old: $OPT_BOOT_ISO"
    log_debug " new: $NEW_ISO"

    log_debug "Modify ISO for the following operations:"
    log_debug "  linux cmdline add:     $CMDLINE_APPEND"
    log_debug "  linux cmdline remove:  $CMDLINE_REMOVE"
    log_debug "  grub add:              $GRUB_APPEND"
    log_debug "  grub remove:           $GRUB_REMOVE"

    which mkisofs &>/dev/null
    if [[ $? -ne 0 ]]; then
        install_package_help mkisofs binary mkisofs
    fi

    mount_iso

    NEW_ISO_DIR=${WORK_DIR}iso.new

    if [[ -d $NEW_ISO_DIR ]]; then
        find $NEW_ISO_DIR | xargs chmod +w
        trace rm -rf $NEW_ISO_DIR
        if [[ $? -ne 0 ]]; then
            die "Failed to remove $NEW_ISO_DIR"
        fi
    fi

    log_debug " Clone existing ISO"

    trace cp -rp $ISO_DIR $NEW_ISO_DIR
    if [[ $? -ne 0 ]]; then
        die "Failed to copy $OPT_BOOT_ISO in $ISO_DIR to $NEW_ISO_DIR"
    fi

    log_debug " Modify new ISO"

    #
    # Avoid using sed in place and mv as some odd nfs issues can prevent
    # remove of files
    #
    local MENU_LST=$NEW_ISO_DIR/boot/grub/menu.lst
    local MENU_LST_NEW=$NEW_ISO_DIR/boot/grub/menu.lst.tmp

    if [[ ! -f $MENU_LST ]]; then
        err "Could not find $MENU_LST to modify"
        return
    fi

    if [[ "$CMDLINE_APPEND" != "" ]]; then
        log_debug " Modify linux cmdline, add '$CMDLINE_APPEND'"

        #
        # Prepend before the platform type, this way we can modify iosxrv or
        # sunstone
        #
        sed "s;\(root=\);$CMDLINE_APPEND \1;g" \
                $MENU_LST >$MENU_LST_NEW
        if [[ $? -ne 0 ]]; then
            df $NEW_ISO_DIR/boot/grub/
            die "Failed to modify grub menu list $NEW_ISO, out of space?"
        fi

        cp $MENU_LST_NEW $MENU_LST
        if [[ $? -ne 0 ]]; then
            die "Failed to copy new grub menu list for $NEW_ISO"
        fi
    fi

    if [[ "$CMDLINE_REMOVE" != "" ]]; then
        for i in $CMDLINE_REMOVE
        do
            log_debug " Modify linux cmdline, remove '$i'"

            sed  "s;$i ;;g" $MENU_LST >$MENU_LST_NEW
            if [[ $? -ne 0 ]]; then
                df $NEW_ISO_DIR/boot/grub/
                die "Failed to modify (remove entry) grub menu list $NEW_ISO, out of space?"
            fi

            cp $MENU_LST_NEW $MENU_LST
            if [[ $? -ne 0 ]]; then
                die "Failed to copy new grub menu list for $NEW_ISO"
            fi
        done
    fi

    if [[ "$GRUB_APPEND" != "" ]]; then
        for i in $GRUB_APPEND
        do
            log_debug " Modify grub, add line '$i'"

            sed "1i$i" $MENU_LST >$MENU_LST_NEW
            if [[ $? -ne 0 ]]; then
                df $NEW_ISO_DIR/boot/grub/
                die "Failed to modify (remove line) grub menu list $NEW_ISO, out of space?"
            fi

            cp $MENU_LST_NEW $MENU_LST
            if [[ $? -ne 0 ]]; then
                die "Failed to copy new grub menu list for $NEW_ISO"
            fi
        done
    fi

    if [[ "$GRUB_REMOVE" != "" ]]; then
        for i in $GRUB_REMOVE
        do
            log_debug " Modify grub, remove line '$i'"

            sed "/$i/d" $MENU_LST >$MENU_LST_NEW
            if [[ $? -ne 0 ]]; then
                df $NEW_ISO_DIR/boot/grub/
                die "Failed to modify (remove line) grub menu list $NEW_ISO, out of space?"
            fi

            cp $MENU_LST_NEW $MENU_LST
            if [[ $? -ne 0 ]]; then
                die "Failed to copy new grub menu list for $NEW_ISO"
            fi
        done
    fi

    #
    # Clean up the cmdline so we don't have gaps from add/removes
    #
    sed "s/ / /g" $MENU_LST > $MENU_LST_NEW
    if [[ $? -eq 0 ]]; then
        cp $MENU_LST_NEW $MENU_LST
    fi

    if [[ "$OPT_DEBUG" != "" ]]; then
        cat $MENU_LST
    fi

    log_debug " Create new ISO"

    trace /bin/rm -f $NEW_ISO
    trace mkisofs -quiet -R -b boot/grub/stage2_eltorito -no-emul-boot -boot-load-size 4 -boot-info-table -o $NEW_ISO $NEW_ISO_DIR
    if [[ $? -ne 0 ]]; then
        die "Failed to create new ISO $NEW_ISO"
    fi

    log_debug " Remove new ISO temp dir"

    find $NEW_ISO_DIR | xargs chmod +w
    trace rm -rf $NEW_ISO_DIR

    log_debug "Baked ISO:"
    log_low " $NEW_ISO"
}

pwdf()
{
    for i in $*
    do
        echo -n `pwd`
        echo -n '/'
        echo $i
    done
}

full_path_name()
{
    local file=$1
    local file_with_path=`pwdf $file`

    if [[ -f "$file_with_path" ]]; then
        echo $file_with_path
        return
    fi

    echo $file
}

#
# CDROM - bootstrap CLI
# Create a disk to carry optional bootstrap CLI
# This will not be booted in XR, will not take up any disk space
# It will be /dev/vdb on the host, mounted briefly to /mnt/iso, before being
# copied off to /etc/sysconfig on XR LXC.
#
create_bootstrap_disk()
{
    if [[ "$OPT_BOOTSTRAP" != "" ]]; then
        if [[ "$PLATFORM_NAME" = "vIOS"  ]]; then

            log "Creating a disk to add VIOS Bootstrap CLI"

            trace_quiet dd if=/dev/zero of=${WORK_DIR}/disk2.img bs=1 count=0 seek=2G
            trace_quiet fatdisk ${WORK_DIR}/disk2.img format size 2G part 0 fat32-lba
            trace_quiet cp $OPT_BOOTSTRAP ios_config.txt
            trace_quiet fatdisk ${WORK_DIR}/disk2.img add ios_config.txt
            add_qemu_cmd "-drive file=${WORK_DIR}/disk2.img,if=virtio,${disk_format}media=disk"
            return
        fi

        log "Creating an ISO disk to add XR Bootstrap CLI"
        local XR_CFG=iosxr_config.txt
        local XR_PROFILE=xrv9k.yaml

        BOOTSTRAP_ISO_NAME=bootstrap.iso
        if [[ -e "${WORK_DIR}${BOOTSTRAP_ISO_NAME}" ]]; then
            rm -rf ${WORK_DIR}${BOOTSTRAP_ISO_NAME}
        fi

        #
        # Check to see if there is anything after the end that looks like
        # configuration and warn if so as the end will stop the rest of
        # the config from being processed.
        #
        local count=$(sed -e '1,/^end$/d' -e '/^\s*$/d' "$OPT_BOOTSTRAP/$XR_CFG" | wc -l)
        if [[ $count -gt 0 ]]; then
            die "Your bootstrap config file has an embedded 'end' in it. This will cause anything following that to be lost. Please fix the config."
        fi

        trace mkisofs -output ${WORK_DIR}${BOOTSTRAP_ISO_NAME} -l -V config-1 --relaxed-filenames --iso-level 2 $OPT_BOOTSTRAP >/dev/null
        if [[ $? -ne 0 ]]; then
            die "Failed to create bootstrap CLI ISO DISK"
        fi

        if [[ "$OPT_DEBUG" != "" ]]; then
            log "Created ISO with bootstrap CLI:"
            isoinfo -l -i ${WORK_DIR}${BOOTSTRAP_ISO_NAME}
            cat "$OPT_BOOTSTRAP/$XR_CFG"
            cat "$OPT_BOOTSTRAP/$XR_PROFILE"
        else
            cat "$OPT_BOOTSTRAP/$XR_CFG"
            cat "$OPT_BOOTSTRAP/$XR_PROFILE"
        fi

        local file_and_path=`full_path_name ${WORK_DIR}${BOOTSTRAP_ISO_NAME}`
        BOOTSTRAP_NAME_VIRSH=$file_and_path
        if [[ $OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO -eq 1 ]]; then
            add_qemu_cmd "-drive file=$file_and_path,if=virtio,media=cdrom,index=3"
        else
            add_qemu_cmd "-drive file=$file_and_path,media=cdrom,index=3"
        fi

    fi
}

#
# Store the disk information selected to be added to the virsh XML
#
# Example disk virsh:
# <disk type='file' device='disk'>
#   <driver name='qemu' type='qcow2'/>
#   <source file='$QCOW2'/>
#   <target dev='vda' bus='virtio'/>
#   <alias name='virtio-disk0'/>
# </disk>
#
# Example qemu cmd line:
# -drive file=/home/rwellum/workdir-rwellnode1/disk1.raw,if=virtio,${disk_format}media=disk,index=1
#
# VIRSH_DISK=disk
# VIRSH_DISK_FILE=/home/rwellum/workdir-rwellnode1/disk1.raw
# VIRSH_BUS=virtio
# VIRSH_DRIVER_TYPE=raw
# VIRSH_DEV=vda
#
# Translates to:
# <disk type='file' device='$VIRSH_DISK'>
#   <driver name='qemu' type='$VIRSH_DRIVER_TYPE'/>
#   <source file='$VIRSH_DISK_FILE'/>
#   <target dev='vda' bus='$VIRSH_BUS'/>
#   <alias name='$VIRSH_BUS-disk0'/>
# </disk>
#
populate_virsh_disk_info()
{
    VIRSH_DISK_FILE=$1
    VIRSH_DISK=$2

    if [[ $OPT_ENABLE_DISK_VIRTIO -eq 1 ]]; then
        VIRSH_BUS=virtio
        VIRSH_DEV=vda
    else
        VIRSH_BUS=ide
        VIRSH_DEV=sda
    fi

    case "$VIRSH_DISK_FILE" in
        *"qcow"* ) VIRSH_DRIVER_TYPE=qcow2;;
        *"iso"* )  VIRSH_DRIVER_TYPE=iso;;
        *"raw"* )  VIRSH_DRIVER_TYPE=raw;;
        *"vmdk"* ) VIRSH_DRIVER_TYPE=vmdk;;
        * ) log "Could not find a known disk type for virsh";;
    esac
}

populate_virsh_cdrom_info()
{
    VIRSH_CDROM=1

    VIRSH_CDROM_DISK_FILE=$1
    VIRSH_CDROM_DISK=$2
    VIRSH_CDROM_DRIVER_TYPE=raw

    # Hard coded - seems to be the only way to get grub to accept a CDROM
    VIRSH_CDROM_BUS=ide
    VIRSH_CDROM_DEV=hdc
}

create_disks()
{
    if [[ $OPT_ENABLE_DISK_VIRTIO -eq 1 ]]; then
        QEMU_DISK_VIRTIO_ARG="if=virtio,${OPT_DISK_CACHE}"
    fi

    #
    # If booting off of a disk then we are good to go and do not need to make
    # any disks.
    #
    if [[ "$OPT_BOOT_DISK" != "" ]]; then
        if [[ "$QEMU_SHOULD_START" = "" ]]; then
            return
        fi

        log "Booting from $OPT_BOOT_DISK"

        if [[ "$OPT_BOOT_ISO" != "" ]]; then
            die "Both -iso and -disk boot specified. Please choose one."
        fi

        local file_and_path=`full_path_name $OPT_BOOT_DISK`
        local disk_format=$(disk_file_to_format_type $file_and_path)
        add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT "

        populate_virsh_disk_info $file_and_path disk

        if [[ "$OPT_BOOTSTRAP" != "" ]]; then
            create_bootstrap_disk
        fi

        return
    fi

    #
    # User is not recreating the disks (no -r). Do the correct thing depending
    # on whether the user has specified an ISO, or has an existing disk - while
    # obeying the -force flag.
    #
    if [[ "$OPT_ENABLE_RECREATE_DISKS" = "" ]]; then
        if [[ -f "$DISK1" ]]; then
            local file_and_path=`full_path_name $DISK1`
            local disk_format=$(disk_file_to_format_type $file_and_path)
            add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT " # vda

            populate_virsh_disk_info $file_and_path disk

            #
            # If not specifying an ISO and we have an existing disk then this
            # looks like a boot of a previous install. Good to go.
            # Note this is irregardless of -f but original functionality
            #
            if [[ "$OPT_BOOT_ISO" = "" ]]; then
                log "No ISO, but have existing disk. Continue booting."
                # include bootstrap CLI if changed
                create_bootstrap_disk
                return
            fi

            #
            # User has entered an ISO with -i, but we also have an existing raw disk:
            # . If the user adds -force(-f), then ignore the ISO and run from the existing disk.
            # . If there is no -f, then warn the user that they need to rerun with either -f or -r.
            # . If the user adds -r, we won't be in this loop at all and will be recreating the disks.
            # This is consistent with the instructions to use -f and -r below.
            #
            if [[ "$OPT_BOOT_ISO" != "" ]]; then
                if [[ "$OPT_FORCE" != "" ]]; then
                    log "Have ISO, but also have existing disk and -f specified. Continue booting."
                    # include bootstrap CLI if changed
                    create_bootstrap_disk
                    return
                fi
            fi

            if [[ "$OPT_FORCE" != "" ]]; then
                if [[ "$QEMU_SHOULD_START" = "" ]]; then
                    return
                fi

                log "Reinstalling from ISO. Disks will be destroyed."
            else
                log "Warning, found existing workspace, disk $DISK1 exists"

                if [[ "$OPT_EXPORT_IMAGES" = "" ]]; then
                    log "-f will launch sunstone from existing disk"
                    log "-r will recreate the disk image and then launch sunstone"
                 else
                    log "-f will create new images from existing disk"
                    log "-r will recreate the disk image then create new images"
                fi
                OPT_EXPORT_IMAGES=
                die "Rerun with either a -f (use existing disk) or -r (create a new disk)"
            fi
        fi
    fi

    #
    # If creating disks then we need an ISO to boot off of.
    #
    if [[ "$OPT_BOOT_ISO" = "" ]]; then
        if [[ -f $DISK1 ]]; then
            local file_and_path=`full_path_name $DISK1`
            local disk_format=$(disk_file_to_format_type $file_and_path)
            add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT " # vda

            populate_virsh_disk_info $file_and_path disk

            log "Booting from existing disk"

            # include bootstrap CLI if changed
            create_bootstrap_disk
            return
        fi

        DISK1=${DISK1%.raw}.qcow2
        if [[ -f $DISK1 ]]; then
            local file_and_path=`full_path_name $DISK1`
            local disk_format=$(disk_file_to_format_type $file_and_path)
            add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT " # vda

            populate_virsh_disk_info $file_and_path disk

            log "Booting from existing disk"

            # include bootstrap CLI if changed
            create_bootstrap_disk
            return
        fi

        die "I need an ISO to boot from as I can find no boot disk, please use the -iso option to specify one."
    fi

    log "Creating disks"

    #
    # Disks
    #
    create_disk $DISK1 $DISK1_SIZE $DISK_TYPE

    local file_and_path=`full_path_name $DISK1`
    local disk_format=$(disk_file_to_format_type $file_and_path)
    add_qemu_cmd "-drive file=$file_and_path,${QEMU_DISK_VIRTIO_ARG}${disk_format}media=disk$OPT_SNAPSHOT,index=1 " # vda

    populate_virsh_disk_info $file_and_path disk

    #
    # QEMU 1.4 and x-data is meant to be faster, but I'm not seeing any
    #
    # QEMU_DISK_VIRTIO_ARG="none"
    # OPT_DISK_CACHE="cache=none,"
    # add_qemu_cmd "-drive if=${QEMU_DISK_VIRTIO_ARG},id=drive1,${OPT_DISK_CACHE}aio=native,format=raw$OPT_SNAPSHOT,index=1,file=$file_and_path"
    # add_qemu_cmd "-device virtio-blk,drive=drive1,scsi=off,config-wce=off,x-data-plane=on"

    #
    # Modify linux command line
    #
    if [[ "$LINUX_CMD_APPEND" != "" || \
          "$LINUX_CMD_REMOVE" != "" ]]; then
        local NEW_ISO=${WORK_DIR}`basename $OPT_BOOT_ISO`$BAKED_SUFFIX;

        modify_iso_linux_cmdline \
            $NEW_ISO \
            "$LINUX_CMD_APPEND" \
            "$LINUX_CMD_REMOVE" \
            "$GRUB_LINE_APPEND" \
            "$GRUB_LINE_REMOVE"

        if [[ $OPT_DISABLE_MODIFY_ISO = "" ]]; then
            if [[ ! -f "$NEW_ISO" ]]; then
                die "Failed to create ISO $OPT_BOOT_ISO$BAKED_SUFFIX"
            fi

            OPT_BOOT_ISO=$NEW_ISO
        fi
    fi

    #
    # CDROM
    #
    # MUST BE BELOW modify_iso_linux_cmdline AS OPT_BOOT_ISO can be changed
    #
    # NOTE grub will not boot with virtio
    #
    file_and_path=`full_path_name $OPT_BOOT_ISO`
    add_qemu_cmd "-drive file=$file_and_path,media=cdrom,index=2 "

    populate_virsh_cdrom_info $file_and_path cdrom

    create_bootstrap_disk
}

qemu_create_scripts()
{
    SLEEP=3

    SOURCE_COMMON_SCRIPT_FUNCTIONS="
err()
{
    echo \"\`date\`\"\": ${LOG_PREFIX}${RED}ERROR: \$*${RESET}\"
}

die()
{
    echo \"\`date\`\"\": ${LOG_PREFIX}${RED}FATAL ERROR: \$*${RESET}\"
    exit 1
}

log()
{
    echo \"\`date\`\"\": ${LOG_PREFIX}${GREEN}\$*${RESET}\"
}

trace()
{
    echo \`date\`\": + \$*\"
    \$* 2>&1
    return \${PIPESTATUS[0]}
}

telnet_wait()
{
    local HOST=\$1
    local PORT=\$2

    cd $PWD
    echo \$\$ >> $MY_TERMINALS_PID_FILE
    cd $LOG_DIR

    log \"Attempting telnet on \$HOST:\$PORT\"
    while true
    do
        echo | telnet \$HOST \$PORT | grep -q \"Connected to\"
        if [[ \$? -eq 0 ]]; then
            log Connected to \$HOST:\$PORT
            return
        fi
        sleep 1
    done
}

cd $PWD
cd $LOG_DIR
"

    if [[ "$OPT_DISABLE_LOGGING" = "" ]]; then

        cat >$TTY1_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY1_PORT

if [[ -r qemu.pid ]]; then
    echo "Root pid: " \`cat qemu.pid\` > con
fi

script -q -f $TTY1_NAME.log -c '$TTY1_TELNET_CMD $TTY_HOST $TTY1_PORT'
%%%

        cat >$TTY2_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY2_PORT
script -q -f $TTY2_NAME.log -c '$TTY2_TELNET_CMD $TTY_HOST $TTY2_PORT'
%%%

        cat >$TTY3_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY3_PORT
script -q -f $TTY3_NAME.log -c '$TTY3_TELNET_CMD $TTY_HOST $TTY3_PORT'
%%%

        cat >$TTY4_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY4_PORT
script -q -f $TTY4_NAME.log -c '$TTY4_TELNET_CMD $TTY_HOST $TTY4_PORT'
%%%
else
        cat >$TTY1_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY1_PORT

if [[ -r qemu.pid ]]; then
    echo "Root pid: " \`cat qemu.pid\` > con
fi

$TTY1_TELNET_CMD $TTY_HOST $TTY1_PORT
%%%

        cat >$TTY2_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY2_PORT
$TTY2_TELNET_CMD $TTY_HOST $TTY2_PORT
%%%

        cat >$TTY3_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY3_PORT
$TTY3_TELNET_CMD $TTY_HOST $TTY3_PORT
%%%

        cat >$TTY4_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $TTY4_PORT
$TTY4_TELNET_CMD $TTY_HOST $TTY4_PORT
%%%
    fi

    chmod +x $TTY1_CMD
    chmod +x $TTY2_CMD
    chmod +x $TTY3_CMD
    chmod +x $TTY4_CMD
}

#
# Validate virsh
#
validate_virsh()
{
    which virt-xml-validate &> /dev/null
    if [[ $? -eq 0 ]]; then
        virt-xml-validate $VIRSH_XML
        if [[ $? -eq 0 ]]; then
            log "VIRSH XML $VIRSH_XML validates"
            VIRSH_VALIDATED=valid
        else
            warn "Warning VIRSH XML $VIRSH_XML did not validate"
            VIRSH_VALIDATED=un-valid
        fi
    else
        warn "VIRSH XML: $VIRSH_XML. Install virt-xml-validate to enable automatic validation"
        VIRSH_VALIDATED=unknown
    fi
}

#
# Use a known working template
# Add in dynamically requested number of interfaces, NIC and Serial
# Add in bootstrap CLI if requested
#
create_virsh()
{
    #
    # If the virsh XML exists already then use the existing UUID
    # (create_uuid uses existing if one is found)
    # Generate the virsh again to enable the telnet ports etc
    #
    if [[ -f $VIRSH_XML ]]; then
        create_uuid
    fi

    if [[ "$OPT_ENABLE_SERIAL_VIRTIO" = "1" ]]; then
        cat > ${WORK_DIR}serial_string.txt <<EOF
    <!-- Use the following to view or create serial ports: -->
    <!--   virsh qemu-monitor-command $DOMAIN_NAME -hmp "info chardev" -->

    <!-- Access: XR Console (telnet localhost $TTY1_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY1_PORT"/>
       <protocol type="telnet"/>
       <target type='virtio' name='vserial0'/>
       <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </serial>
    <!-- Access: XR Aux (telnet localhost $TTY2_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY2_PORT"/>
       <protocol type="telnet"/>
       <target type='virtio' name='vserial0'/>
       <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </serial>
    <!-- Access: Admin / Calvados (telnet localhost $TTY3_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY3_PORT"/>
       <protocol type="telnet"/>
       <target type='virtio' name='vserial0'/>
       <address type='virtio-serial' controller='0' bus='0' port='3'/>
    </serial>
    <!-- Access: HOST VM (telnet localhost $TTY4_PORT)  -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY4_PORT"/>
       <protocol type="telnet"/>
       <target type='virtio' name='vserial0'/>
       <address type='virtio-serial' controller='0' bus='0' port='4'/>
    </serial>

  <!-- virsh console instead of telnet for first serial port -->
  <!-- <console type='pty'> -->
  <!--  <target type='serial' port='0'/> -->
  <!-- </console> -->
EOF
    else
        cat > ${WORK_DIR}serial_string.txt <<EOF
    <!-- Use the following to view or create serial ports: -->
    <!--   virsh qemu-monitor-command $DOMAIN_NAME -hmp "info chardev" -->

    <!-- Access: XR Console (telnet localhost $TTY1_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY1_PORT"/>
       <protocol type="telnet"/>
       <target port="0"/>
    </serial>
    <!-- Access: XR Aux (telnet localhost $TTY2_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY2_PORT"/>
       <protocol type="telnet"/>
       <target port="1"/>
    </serial>
    <!-- Access: Admin / Calvados (telnet localhost $TTY3_PORT) -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY3_PORT"/>
       <protocol type="telnet"/>
       <target port="2"/>
    </serial>
    <!-- Access: HOST VM (telnet localhost $TTY4_PORT)  -->
    <serial type='tcp'>
       <source mode="bind" host="$TTY_HOST" service="$TTY4_PORT"/>
       <protocol type="telnet"/>
       <target port="3"/>
    </serial>

  <!-- virsh console instead of telnet for first serial port -->
  <!-- <console type='pty'> -->
  <!--  <target type='serial' port='0'/> -->
  <!-- </console> -->
EOF
    fi

    grep -q "element name=\"memoryBacking\"" /usr/share/libvirt/schemas/*
    if [[ $? -eq 0 ]]; then
        if [[ "$OPT_HUGE_PAGES_CHECK" = "1" ]]; then
            cat > ${WORK_DIR}huge_string.txt <<EOF

    <memoryBacking>
EOF

            grep -q "element name=\"hugepages\"" /usr/share/libvirt/schemas/*
            if [[ $? -eq 0 ]]; then
                cat >> ${WORK_DIR}huge_string.txt <<EOF

        <hugepages/>
        <!-- You will need to mount huge pages and possibly restart libvirtd -->
        <!-- if they were not mounted when it was launched -->
EOF
            fi

            grep -q "element name=\"page\"" /usr/share/libvirt/schemas/*
            if [[ $? -eq 0 ]]; then
                cat >> ${WORK_DIR}huge_string.txt <<EOF

        <page size="1" unit="G"/>
        <!-- future: use numa zone for dataplane, nodeset="..."/> -->
EOF
            fi

            if [[ "$OPT_NUMA_RED_HAT" = "" ]]; then
                grep -q "element name=\"nosharepages\"" /usr/share/libvirt/schemas/*
                if [[ $? -eq 0 ]]; then
                    cat >> ${WORK_DIR}huge_string.txt <<EOF

        <nosharepages/>
        <!-- Instructs hypervisor to disable KSM for this domain. -->
EOF
                fi
            fi

            grep -q "element name=\"locked\"" /usr/share/libvirt/schemas/*
            if [[ $? -eq 0 ]]; then
                cat >> ${WORK_DIR}huge_string.txt <<EOF

        <locked/>
        <!-- Memory pages belonging to the domain will be locked in host's -->
        <!-- memory and the host will not be allowed to swap them out.     -->
EOF
            fi

            cat >> ${WORK_DIR}huge_string.txt <<EOF

    </memoryBacking>
EOF
        else
            cat > ${WORK_DIR}huge_string.txt <<EOF

    <!-- memoryBacking -->
        <!-- You will need to mount huge pages and possibly restart libvirtd -->
        <!-- if they were not mounted when it was launched -->

        <!-- hugepages/ -->
        <!-- You will need to mount huge pages and possibly restart libvirtd -->
        <!-- if they were not mounted when it was launched -->

        <!-- page size="1" unit="G"/ -->
        <!-- future: use numa zone for dataplane, nodeset="..."/> -->
EOF

            if [[ "$OPT_NUMA_RED_HAT" = "" ]]; then
                cat >> ${WORK_DIR}huge_string.txt <<EOF
        <!-- nosharepages/ -->
        <!-- Instructs hypervisor to disable KSM for this domain. -->
EOF
            fi

            cat >> ${WORK_DIR}huge_string.txt <<EOF
        <!-- locked/ -->
        <!-- Memory pages belonging to the domain will be locked in host's -->
        <!-- memory and the host will not be allowed to swap them out.     -->
    <!-- /memoryBacking -->
EOF
        fi
    fi

    grep -q numatune /usr/share/libvirt/schemas/*
    if [[ $? -eq 0 ]]; then
        if [[ "$OPT_NUMA_NODES" != "" ]]; then
            cat > ${WORK_DIR}numa_string.txt <<EOF

    <numatune>
        <!-- memory mode="strict" nodeset="1-$TOTAL_CORES"/ -->

        <!-- If supported by libvirt, uncomment the below: -->
        <!-- Libvirt is also buggy here and can add one to the numa cell... -->
        <!-- memnode cellid="$OPT_NUMA_NODES" mode="preferred" nodeset="1-$TOTAL_CORES"/ -->
    </numatune>
EOF
        else
            cat > ${WORK_DIR}numa_string.txt <<EOF

    <!-- numatune -->
        <!-- memory mode="strict" nodeset="1-$TOTAL_CORES"/ -->

        <!-- If supported by libvirt, uncomment the below: -->
        <!-- Libvirt is also buggy here and can add one to the numa cell... -->
        <!-- memnode cellid="$OPT_NUMA_NODES" mode="preferred" nodeset="1-$TOTAL_CORES"/ -->
    <!-- /numatune -->
EOF
        fi
    fi

    #
    # Create correct disk to point to based on qemu line in create_disks()
    #
    cat > ${WORK_DIR}disk_string.txt <<EOF

    <!-- HDA Disk -->
    <disk type='file' device='$VIRSH_DISK'>
     <driver name='qemu' type='$VIRSH_DRIVER_TYPE'/>
     <source file='$VIRSH_DISK_FILE'/>
     <target dev='$VIRSH_DEV' bus='$VIRSH_BUS'/>
     <alias name='$VIRSH_BUS-disk0'/>
    </disk>
EOF

    echo > ${WORK_DIR}cdrom_string.txt

    if [[ "$VIRSH_CDROM" != "" ]]; then
        #
        # Create correct CDROM ISO disk to point to based on qemu line in create_disks()
        #
        cat > ${WORK_DIR}cdrom_string.txt <<EOF

     <!-- CDROM HDB Disk -->
     <disk type='file' device='$VIRSH_CDROM_DISK'>
      <driver name='qemu' type='$VIRSH_CDROM_DRIVER_TYPE'/>
      <source file='$VIRSH_CDROM_DISK_FILE'/>
      <target dev='$VIRSH_CDROM_DEV' bus='$VIRSH_CDROM_BUS'/>
      <alias name='$VIRSH_CDROM_BUS-cdrom'/>
     </disk>
EOF
    fi

    #
    # Create Interface sections
    # Find the number of GE's created, get a mac address for each
    # Save to a file to be inserted into the final VIRSH XML
    #
    get_next_mac_addresses

    add_qemu_and_vhost_net
    add_qemu_and_csum_offload
    add_qemu_and_queues

    # Host interface section
    for i in $(seq 1 $OPT_HOST_NICS)
    do
        MAC=${MAC_HOST_ETH[$i]}
        BRIDGE=${BRIDGE_HOST_ETH[$i]}
        TAP=${TAP_HOST_ETH[$i]}

        let z=i-1
        cat >>${WORK_DIR}host_interface_string.txt <<EOF

    <!-- Host Interface $i -->
    <interface type='bridge'>
      <mac address='$MAC'/>
      <source bridge='$BRIDGE'/>
      <target dev='$TAP'/>
      <model type='$VIRSH_HOST_NIC'/>
      <driver $VIRSH_OPT_HOST_NIC>
EOF

        if [[ "$VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS" != "" ]]; then
            cat >>${WORK_DIR}host_interface_string.txt <<EOF
      <!-- Uncomment the below to enable -->
      <!--host $VIRSH_OPT_HOST_NIC_EXTRA_HOST_OPTS /-->
EOF
        fi
        if [[ "$VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS" != "" ]]; then
            cat >>${WORK_DIR}host_interface_string.txt <<EOF
      <!-- Uncomment the below to enable -->
      <!-- guest $VIRSH_OPT_HOST_NIC_EXTRA_GUEST_OPTS /-->
EOF
        fi

        cat >>${WORK_DIR}host_interface_string.txt <<EOF
      </driver>
      <alias name='hostnet${z}'/>
    </interface>
EOF
    done

    # Data interface section
    for i in $(seq 1 $OPT_DATA_NICS)
    do
        MAC=${MAC_DATA_ETH[i]}
        BRIDGE=${BRIDGE_DATA_ETH[$i]}
        TAP=${TAP_DATA_ETH[$i]}

        let z=i-1
        cat >>${WORK_DIR}data_interface_string.txt <<EOF

    <!-- Data Interface $i -->
    <interface type='bridge'>
      <mac address='$MAC'/>
      <source bridge='$BRIDGE'/>
      <target dev='$TAP'/>
      <model type='$VIRSH_DATA_NIC'/>
      <driver $VIRSH_OPT_DATA_NIC>
EOF

        if [[ "$VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS" != "" ]]; then
            cat >>${WORK_DIR}data_interface_string.txt <<EOF
      <!-- Uncomment the below to enable -->
      <!-- host $VIRSH_OPT_DATA_NIC_EXTRA_HOST_OPTS /-->
EOF
        fi
        if [[ "$VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS" != "" ]]; then
            cat >>${WORK_DIR}data_interface_string.txt <<EOF
      <!-- Uncomment the below to enable -->
      <!-- guest $VIRSH_OPT_DATA_NIC_EXTRA_GUEST_OPTS /-->
EOF
        fi

        cat >>${WORK_DIR}data_interface_string.txt <<EOF
      </driver>
      <alias name='datanet${z}'/>
    </interface>
EOF
    done

    # hostdev section
    for PCI in $OPT_PCI_LIST
    do
       local DOMAIN=`echo $PCI | awk -F: '{print $1}'`
       local BUS=`echo $PCI | awk -F: '{print $2}'`
       local SLOT=`echo $PCI | awk -F: '{print $3}' | awk -F. '{print $1}'`
       local FUNCTION=`echo $PCI | awk -F. '{print $2}'`
        cat >>${WORK_DIR}data_interface_string.txt <<EOF
    <hostdev mode='subsystem' type='pci' managed='no'>
      <source>
        <address domain='0x$DOMAIN'
                 bus='0x$BUS'
                 slot='0x$SLOT'
                 function='0x$FUNCTION'/>
      </source>
    </hostdev>
EOF
    done

    # Add mlock support to qemu other args
    if [[ "$OPT_MLOCK" = "1" ]]; then
       cat >> ${WORK_DIR}mlockstring.txt <<EOF

    <!-- Turn mlock on -->
    <qemu:arg value='-realtime'/>
    <qemu:arg value='mlock=on'/>
EOF
    fi

    # Optional bootstrap CLI
    if [[ "$OPT_BOOTSTRAP" != "" ]]; then
        # If needed generate the bootstrap CLI ISO
        create_bootstrap_disk

        cat >> ${WORK_DIR}bootstrap_string.txt <<EOF

    <!-- Bootstrap CLI ISO -->
    <disk type='file' device='cdrom'>
     <driver name='qemu' type='raw'/>
      <source file='$BOOTSTRAP_NAME_VIRSH'/>
      <target dev='vdc' bus='virtio'/>
      <readonly/>
      <alias name='bootstrap_CLI'/>
    </disk>
EOF
    else
        # Add commented bootstrap CLI so user can see how to add one manually
        cat >> ${WORK_DIR}bootstrap_string.txt <<EOF

    <!-- Example Bootstrap CLI ISO -->
    <!-- <disk type='file' device='cdrom'>                 -->
    <!--  <driver name='qemu' type='raw'/>                 -->
    <!--  <source file='<ISO with file iosxr_config.txt'/> -->
    <!--  <target dev='vdc' bus='virtio'/>                 -->
    <!--  <readonly/>                                      -->
    <!--  <alias name='bootstrap_CLI'/>                    -->
    <!-- </disk>                                           -->
EOF
    fi

    #
    # If this is exported virsh (not running) then set the ports to zero as
    # customer will replace with their own or use qemu
    # virsh qemu-monitor-command $DOMAIN_NAME --hmp "info chardev"
    #
    if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
        TTY1_PORT=0
        TTY2_PORT=0
        TTY3_PORT=0
        TTY4_PORT=0
        # Similarly, set a "typical" kvm path as default.
        local KVM_EXEC_NO_SUDO="/usr/bin/kvm"
    else
        # We are booting virsh, so use the locally preferred kvm path:
        local KVM_EXEC_NO_SUDO=`echo $KVM_EXEC | sed 's/sudo //g'`
    fi

    # Rest of the virsh
    get_total_cores

    local add_node="_$OPT_NODE_NAME"
    DOMAIN_NAME=${PLATFORM_NAME}_${OPT_ENABLE_HW_PROFILE}${add_node}_virsh

    cat >$VIRSH_XML <<EOF

<!--

********************************************************************************
*                                                                              *
* WARNING: THIS IS A TEMPLATE virsh XML file based on user inputs when the     *
* included QCOW2 image was created.                                            *
*                                                                              *
* Changes to this xml configuration should be made using:                      *
*   virsh edit <name>                                                          *
* or other application using the libvirt API.                                  *
*                                                                              *
* This virsh XM was verified on CentOS release 6.6 (Final) and                 *
* Ubuntu 14.04.3 LTS.                                                          *
*                                                                              *
********************************************************************************

-->


<domain type='kvm' id='1' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>$DOMAIN_NAME</name>
  <uuid>$UUID</uuid>
  <title>${PLATFORM_VIRSH_TITLE}</title>
  <memory unit='MB'>$OPT_PLATFORM_MEMORY_MB</memory>
  <currentMemory unit='MB'>$OPT_PLATFORM_MEMORY_MB</currentMemory>
  <vcpu placement='static' cpuset="$OPT_CPU_LIST">$TOTAL_CORES</vcpu>
  <cpu mode='host-passthrough'/>

  <!-- HugeSection (for huge page support) -->

  <!-- NumaSection (for numa support) -->

  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
    <bootmenu enable='yes'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>$KVM_EXEC_NO_SUDO</emulator>

    <!-- DiskSection -->

    <!-- CdromSection -->

    <!-- BootstrapSection -->

    <controller type='ide' index='0'>
      <alias name='ide0'/>
    </controller>

    <!-- HostInterfaceSection (order: mgmt/ha/development) -->

    <!-- DataInterfaceSection (order: GIGE0, GIGE1 .. etc) -->

    <!-- SerialPortSection -->

  </devices>
  <qemu:commandline>
     <!-- Add extra monitor port for the virsh monitor tab -->
     <qemu:arg value='-chardev'/>
     <qemu:arg value='socket,id=monitor0,host=$TTY_HOST,port=$QEMU_PORT,ipv4,server,nowait,telnet'/>
     <qemu:arg value='-monitor'/>
     <qemu:arg value='chardev:monitor0'/>
     <!-- OptionalArgs -->
  </qemu:commandline>
</domain>
EOF

    #
    # Add in the dynamic XML, Interfaces and Bootstrap
    #
    sed -i "/SerialPortSection/r ${WORK_DIR}serial_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}serial_string.txt

    sed -i "/HugeSection/r ${WORK_DIR}huge_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}huge_string.txt

    sed -i "/NumaSection/r ${WORK_DIR}numa_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}numa_string.txt

    sed -i "/DiskSection/r ${WORK_DIR}disk_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}disk_string.txt

    sed -i "/HostInterfaceSection/r ${WORK_DIR}host_interface_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}host_interface_string.txt

    sed -i "/DataInterfaceSection/r ${WORK_DIR}data_interface_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}data_interface_string.txt

    sed -i "/OptionalArgs/r ${WORK_DIR}mlockstring.txt" $VIRSH_XML
    rm -f ${WORK_DIR}mlockstring.txt

    sed -i "/BootstrapSection/r ${WORK_DIR}bootstrap_string.txt" $VIRSH_XML
    rm -f ${WORK_DIR}bootstrap_string.txt

    if [[ "$VIRSH_CDROM" != "" ]]; then
        sed -i "/CdromSection/r ${WORK_DIR}cdrom_string.txt" $VIRSH_XML
        rm -f ${WORK_DIR}cdrom_string.txt
    fi

    validate_virsh

    cat $VIRSH_XML
}

qemu_generate_cmd()
{
    ##################################################################
    # WARNING sanity uses the output of this function. DO NOT REMOVE #
    ##################################################################

    cat >$TTY0_CMD_QEMU <<%%
$*
%%
    sed 's/ \-/ \\\n      -/g' $TTY0_CMD_QEMU > $TTY0_CMD_QEMU.tmp
    cp $TTY0_CMD_QEMU.tmp $TTY0_CMD_QEMU

    if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
        log_debug "QEMU command line:"
        log_debug " $TTY0_CMD_QEMU"
    fi

    ##################################################################
    # WARNING sanity uses the output of this function. DO NOT REMOVE #
    ##################################################################
}

qemu_launch()
{
    WHICH=$1
    shift

    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    LOG=$LOG_DIR/$TTY0_NAME.log

cat >$TTY0_PRE_CMD <<%%%
#!/bin/bash

qemu_pin()
{
    local PORT=\$1
    local SAVE_IFS=\$IFS
    local CPUID=0
    local CPUS=

    while true
    do
        sleep 1

        local got_one=0

        CPUS=\`(sleep 2; echo 'info cpus'; sleep 2) | telnet $TTY_HOST \$PORT 2>/dev/null\`
        for TOKEN in \$CPUS
        do
            TOKEN=\`echo \$TOKEN | tr -d '\r'\`

            echo \$TOKEN | grep -q "^thread_id.[0-9]*"
            if [[ \$? -eq 0 ]]; then

                got_one=1

                local TID=\`echo \$TOKEN | sed 's/.*=//g'\`

                local CPUID_FIELD=\`expr \$CPUID + 1\`
                local PIN_TO=\`echo $OPT_CPU_LIST | cut -d , -f \$CPUID_FIELD\`

                if [[ "\$PIN_TO" = "" ]]; then
                    err "Not enough CPUs were given to pin all threads"
                    break
                fi

                log "Pinning thread \$TID to cpu \$PIN_TO"
                trace taskset -cp \$PIN_TO \$TID || sudo trace taskset -cp \$PIN_TO \$TID
                if [[ \$? -eq 0 ]]; then
                    CPUID=\`expr \$CPUID + 1\`
                else
                    err "Failed to pin thread \$TID to cpu \$PIN_TO"
                fi
            fi
        done

        if [[ \$got_one -eq 1 ]]; then
            return
        fi
    done
}

$SOURCE_COMMON_SCRIPT_FUNCTIONS

if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
    log "Running QEMU..."
fi
cd $PWD

KVM_EXEC_PREFIX=
if [[ "$INCLUDE_TMPDIR" != "" ]]; then
    if [[ "$TMPDIR" != "" ]]; then
        KVM_EXEC_PREFIX="\${KVM_EXEC_PREFIX}TMPDIR=$TMPDIR "
    fi
fi

if [[ "$NUMA_MEM_ALLOC" != "" ]]; then
    KVM_EXEC_PREFIX="\${KVM_EXEC_PREFIX}${NUMA_MEM_ALLOC} "
fi

if [[ "$OPT_BOOT_VIRSH" != "" ]]; then
    # If running from virsh (--boot-virsh) then use virsh and not qemu directly
    KVM_ARGS="virsh create $VIRSH_XML"
else
    #
    # Add any commands that need to run on the same line as kvm
    #
    KVM_ARGS="$*"
    echo $* | grep -q sudo
    if [[ \$? -eq 0 ]]; then
        KVM_ARGS=\$(echo \${KVM_ARGS} | sed 's/^sudo //g')
        KVM_ARGS="sudo \${KVM_EXEC_PREFIX}\${KVM_ARGS}"
    else
        KVM_ARGS="\${KVM_EXEC_PREFIX}\${KVM_ARGS}"
    fi
fi

if [[ "$OPT_ENABLE_MONITOR" -eq 0 ]]; then
    #
    # Now start the VM in the foreground
    #
    echo "\${KVM_ARGS}" | sed -e 's/ \-/ \\\\\n      -/g'
    \${KVM_ARGS} 2>&1 | tee -a $LOG_DIR/QEMU.output.log
    exit 0
fi

#
# Now start the VM in the background
#
echo "\${KVM_ARGS} &" | sed -e 's/ \-/ \\\\\n      -/g'

#
# Need to wrap in bash as TMPDIR seems to cause issues when backgrounding
# and we try to run TMPDIR as the target
#
(/bin/bash -c "\${KVM_ARGS}" 2>&1 | tee -a $LOG_DIR/QEMU.output.log) &

#
# More robust polling to make sure the monitor is really up. It can take a few
# seconds.
#
QEMU_FAIL_COUNT=0

while true
do
    QEMU_FAIL_COUNT=\`expr \$QEMU_FAIL_COUNT + 1\`
    if [[ \$QEMU_FAIL_COUNT -gt 300 ]]; then
        cat $LOG_DIR/QEMU.output.log
        err "Failed to start QEMU. Please check $LOG_DIR/QEMU.output.log"
        exit 1
    fi

    log "Connecting to the QEMU monitor (\$QEMU_FAIL_COUNT)..."
    ( echo; sleep 1 ) | telnet $TTY_HOST $QEMU_PORT | grep "QEMU.*monitor"
    if [[ \$? -eq 0 ]]; then
        break
    fi

    #
    # This one is hit so often, try and help the user.
    #
    grep -q "Failed to initgroups" $LOG_DIR/QEMU.output.log
    if [[ \$? -eq 0 ]]; then
        log "Failed to start KVM, initgroups error. Removing -runas and retrying"

        KVM_ARGS=\$(echo \${KVM_ARGS} | sed 's/-runas [a-z0-9]* //g')
        echo "\${KVM_ARGS} &" | sed -e 's/ \-/ \\\\\n      -/g'

        /bin/rm -f $LOG_DIR/QEMU.output.log
        (/bin/bash -c "\${KVM_ARGS}" 2>&1 | tee -a $LOG_DIR/QEMU.output.log) &
    fi

    #
    # This one is hit so often, try and help the user.
    #
    grep -q "Failed to assign device" $LOG_DIR/QEMU.output.log
    if [[ \$? -eq 0 ]]; then
        device=\`grep "device pci-assign" $LOG_DIR/QEMU.output.log | sed -e 's/.*host=//g' -e 's/: Device.*//g'\`
        device_short=\`echo "\$device" | sed 's/^0000://g'\`
        pci=\`lspci -n | grep "\$device_short"| sed 's/.*: //g'\`

        err "PCI passthrough assign failed for device $device"
        log "This might work:"
        log "echo \$pci > /sys/bus/pci/drivers/pci-stub/new_id"
        log "echo \$device > /sys/bus/pci/drivers/pci-stub/unbind"
        log "echo \$device > /sys/bus/pci/drivers/pci-stub/bind"
        log "echo \$pci > /sys/bus/pci/drivers/pci-stub/remove_id"
        log ""
        log "Other things to try:"
        log ""
        log "Check DMAR / IOMMU is seen:"
        log "dmesg | grep -e DMAR -e IOMMU"
        log ""
        log "Check kvm is seen:"
        log "lsmod | grep kvm"
        log ""
        log "Check pci_stub kernel is loaded"
        log "lsmod | grep pci"
        log ""
        log "And this, but should not be needed as this tool does it for you:"
        log "echo 1  > /sys/module/kvm/parameters/allow_unsafe_assigned_interrupts"

        exit 1
    fi
done

if [[ "$OPT_CPU_LIST" != "" ]]; then
    log "Performing CPU pinning..."
    qemu_pin $QEMU_PORT
fi

log "Collecting VM PCI info..."
( echo 'info pci'; sleep 3 ) | telnet $TTY_HOST $QEMU_PORT

log "Collecting VM CPU info..."
( echo 'info cpus'; sleep 3 ) | telnet $TTY_HOST $QEMU_PORT

exit 0
%%%

    chmod +x $TTY0_PRE_CMD
    chmod +x $TTY1_CMD
    chmod +x $TTY2_CMD
    chmod +x $TTY3_CMD
    chmod +x $TTY4_CMD

    if [[ "$OPT_DELAY" != "" ]]; then
        sleep $OPT_DELAY
    fi

    #
    # Kick off QEMU in the background and do cpu pinning or whatever we need
    #
    if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
        log_debug "Start QEMU launch..."
        $TTY0_PRE_CMD
        if [[ $? -ne 0 ]]; then
            die "QEMU launch failed"
        fi

        log "QEMU launched"

        I_STARTED_VM=1

        wait_for_qemu_start
        if [[ ! -s $MY_QEMU_PID_FILE ]]; then
            die "QEMU did not start"
        fi
    fi

    #
    # Now create a telnet wrapper to access the QEMU monitor
    #
    cat >$TTY0_CMD <<%%%
$SOURCE_COMMON_SCRIPT_FUNCTIONS
telnet_wait $TTY_HOST $QEMU_PORT
script -a -f \`basename $LOG\` -c "$TTY0_TELNET_CMD $TTY_HOST $QEMU_PORT"
%%%

    chmod +x $TTY0_CMD

    if [[ "$OPT_UI_LOG" = "1" ]]; then
        log "Launching background telnet sessions"

        if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
            nohup sudo_check_trace /bin/bash -c $TTY0_CMD &>/dev/null &
            echo $! >> $MY_TERMINALS_PID_FILE
        fi

        nohup sudo_check_trace /bin/bash -c $TTY1_CMD &> /dev/null &
        echo $! >> $MY_TERMINALS_PID_FILE
        nohup sudo_check_trace /bin/bash -c $TTY2_CMD &> /dev/null &
        echo $! >> $MY_TERMINALS_PID_FILE

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            nohup sudo_check_trace /bin/bash -c $TTY3_CMD &> /dev/null &
            echo $! >> $MY_TERMINALS_PID_FILE
            nohup sudo_check_trace /bin/bash -c $TTY4_CMD &> /dev/null &
            echo $! >> $MY_TERMINALS_PID_FILE
        fi

    elif [[ "$OPT_UI_SCREEN" = "1" ]]; then
        log "Launching screen sessions"

        if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
            screen -t "${WHICH}${TTY0_NAME}" /bin/bash -c "/bin/bash $PWD/$TTY0_CMD"
            sleep 1
        fi

        screen -t "${WHICH}${TTY1_NAME}" /bin/bash -c "/bin/bash $PWD/$TTY1_CMD"
        sleep 1
        screen -t "${WHICH}${TTY2_NAME}" /bin/bash -c "/bin/bash $PWD/$TTY2_CMD"
        sleep 1

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            screen -t "${WHICH}${TTY3_NAME}" /bin/bash -c "/bin/bash $PWD/$TTY3_CMD"
            sleep 1
            screen -t "${WHICH}${TTY4_NAME}" /bin/bash -c "/bin/bash $PWD/$TTY4_CMD"
            sleep 1
        fi

    elif [[ "$OPT_UI_TMUX" = "1" ]]; then
        log "Launching tmux session"

        if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
            TMPDIR= TMUX= tmux new-session -d -s "${WHICH}" -n "${TTY0_NAME}" "/bin/bash $PWD/$TTY0_CMD"
            TMPDIR= tmux new-window -t "${WHICH}" -n "${TTY1_NAME}" "/bin/bash $PWD/$TTY1_CMD"
        else
            TMPDIR= TMUX= tmux new-session -d -s "${WHICH}" -n "${TTY1_NAME}" "/bin/bash $PWD/$TTY1_CMD"
        fi

        TMPDIR= tmux new-window -t "${WHICH}" -n "${TTY2_NAME}" "/bin/bash $PWD/$TTY2_CMD"

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            TMPDIR= tmux new-window -t "${WHICH}" -n "${TTY3_NAME}" "/bin/bash $PWD/$TTY3_CMD"
            TMPDIR= tmux new-window -t "${WHICH}" -n "${TTY4_NAME}" "/bin/bash $PWD/$TTY4_CMD"
        fi

        TMPDIR= tmux select-window -t "${WHICH}:${TTY1_NAME}"
        TMPDIR= tmux switch-client -t "${WHICH}"

    elif [[ "$OPT_UI_XTERM" = "1" ]]; then
        log "Launching xterms"

        if [[ "$OPT_TERM_BG_COLOR" != "" ]]; then
            OPT_TERM="${OPT_TERM}-bg $OPT_TERM_BG_COLOR "
        fi

        if [[ "$OPT_TERM_FG_COLOR" != "" ]]; then
            OPT_TERM="${OPT_TERM}-fg $OPT_TERM_FG_COLOR "
        fi

        if [[ "$OPT_TERM_FONT" != "" ]]; then
            OPT_TERM="${OPT_TERM}-font $OPT_TERM_FONT "
        fi

        if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
            xterm -sb -sl 10000 $OPT_TERM -title "${WHICH}${TTY0_NAME}" -e "/bin/bash $TTY0_CMD" &
            echo $! >> $MY_TERMINALS_PID_FILE
        fi

        xterm -sb -sl 10000 $OPT_TERM -title "${WHICH}${TTY1_NAME}" -e "/bin/bash $TTY1_CMD" &
        echo $! >> $MY_TERMINALS_PID_FILE
        xterm -sb -sl 10000 $OPT_TERM -title "${WHICH}${TTY2_NAME}" -e "/bin/bash $TTY2_CMD" &
        echo $! >> $MY_TERMINALS_PID_FILE

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            xterm -sb -sl 10000 $OPT_TERM -title "${WHICH}${TTY3_NAME}" -e "/bin/bash $TTY3_CMD" &
            echo $! >> $MY_TERMINALS_PID_FILE
            xterm -sb -sl 10000 $OPT_TERM -title "${WHICH}${TTY4_NAME}" -e "/bin/bash $TTY4_CMD" &
            echo $! >> $MY_TERMINALS_PID_FILE
        fi
        sleep 1

    elif [[ "$OPT_UI_KONSOLE" = "1" ]]; then
        log "Launching konsole"

        if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
            cat <<%% >${LOG_DIR}.konsole
title: ${WHICH}${TTY0_NAME};; command: /bin/bash $PWD/$TTY0_CMD
title: ${WHICH}${TTY1_NAME};; command: /bin/bash $PWD/$TTY1_CMD
title: ${WHICH}${TTY2_NAME};; command: /bin/bash $PWD/$TTY2_CMD
%%
        else
            cat <<%% >${LOG_DIR}.konsole
title: ${WHICH}${TTY1_NAME};; command: /bin/bash $PWD/$TTY1_CMD
title: ${WHICH}${TTY2_NAME};; command: /bin/bash $PWD/$TTY2_CMD
%%
        fi

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            cat <<%% >>${LOG_DIR}.konsole
title: ${WHICH}${TTY3_NAME};; command: /bin/bash $PWD/$TTY3_CMD
title: ${WHICH}${TTY4_NAME};; command: /bin/bash $PWD/$TTY4_CMD
%%
        fi

        if [[ "$OPT_TERM_PROFILE" != "" ]]; then
            OPT_TERM="${OPT_TERM}-profile $OPT_TERM_PROFILE "
        fi

        konsole $OPT_TERM --title "${WHICH}" --tabs-from-file ${LOG_DIR}.konsole
        echo $! >> $MY_TERMINALS_PID_FILE

    elif [[ "$OPT_UI_MRXVT" = "1" ]]; then
        log "Launching mrxvt"
        log_debug " $MRXVT"

        if [[ "$OPT_TERM_BG_COLOR" != "" ]]; then
            OPT_TERM="${OPT_TERM}-bg $OPT_TERM_BG_COLOR "
        fi

        if [[ "$OPT_TERM_FG_COLOR" != "" ]]; then
            OPT_TERM="${OPT_TERM}-fg $OPT_TERM_FG_COLOR "
        fi

        if [[ "$OPT_TERM_FONT" != "" ]]; then
            OPT_TERM="${OPT_TERM}-font $OPT_TERM_FONT "
        fi

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            if [[ $OPT_ENABLE_MONITOR -eq 0 ]]; then
                # No monitor
                $MRXVT -sb -sl 5000 -title ${WHICH} -ip 2,3,4,5  \
                       -geometry 100x24                               \
                       $OPT_TERM                                      \
                       -profile2.tabTitle ${WHICH}${TTY1_NAME}        \
                       -profile2.command "/bin/bash $PWD/$TTY1_CMD"     \
                       -profile3.tabTitle ${WHICH}${TTY2_NAME}        \
                       -profile3.command "/bin/bash $PWD/$TTY2_CMD"     \
                       -profile4.tabTitle ${WHICH}${TTY3_NAME}        \
                       -profile4.command "/bin/bash $PWD/$TTY3_CMD"     \
                       -profile5.tabTitle ${WHICH}${TTY4_NAME}        \
                       -profile5.command "/bin/bash $PWD/$TTY4_CMD"     \
                &
            else
                #
                # Putting profile 1 last seems to allow 5 tabs...
                #
                $MRXVT -sb -sl 5000 -title ${WHICH} -ip 1,2,3,4,5  \
                       -geometry 100x24                               \
                       $OPT_TERM                                      \
                       -profile2.tabTitle ${WHICH}${TTY1_NAME}        \
                       -profile2.command "/bin/bash $PWD/$TTY1_CMD"     \
                       -profile3.tabTitle ${WHICH}${TTY2_NAME}        \
                       -profile3.command "/bin/bash $PWD/$TTY2_CMD"     \
                       -profile4.tabTitle ${WHICH}${TTY3_NAME}        \
                       -profile4.command "/bin/bash $PWD/$TTY3_CMD"     \
                       -profile5.tabTitle ${WHICH}${TTY4_NAME}        \
                       -profile5.command "/bin/bash $PWD/$TTY4_CMD"     \
                       -profile1.tabTitle ${WHICH}${TTY0_NAME}        \
                       -profile1.command "/bin/bash $PWD/$TTY0_CMD"     \
                &
            fi
        else
            if [[ "$OPT_ENABLE_MONITOR" -eq 0 ]]; then
                $MRXVT -sb -sl 5000 -title ${WHICH} -ip 1,2      \
                       -geometry 100x24                               \
                       $OPT_TERM                                      \
                       -profile2.tabTitle ${WHICH}${TTY1_NAME}        \
                       -profile2.command "/bin/bash $PWD/$TTY1_CMD"     \
                       -profile3.tabTitle ${WHICH}${TTY2_NAME}        \
                       -profile3.command "/bin/bash $PWD/$TTY2_CMD"     \
                &
            else
                $MRXVT -sb -sl 5000 -title ${WHICH} -ip 1,2,3      \
                       -geometry 100x24                               \
                       $OPT_TERM                                      \
                       -profile1.tabTitle ${WHICH}${TTY0_NAME}        \
                       -profile1.command "/bin/bash $PWD/$TTY0_CMD"     \
                       -profile2.tabTitle ${WHICH}${TTY1_NAME}        \
                       -profile2.command "/bin/bash $PWD/$TTY1_CMD"     \
                       -profile3.tabTitle ${WHICH}${TTY2_NAME}        \
                       -profile3.command "/bin/bash $PWD/$TTY2_CMD"     \
                &
            fi
        fi

        echo $! >> $MY_TERMINALS_PID_FILE

    else
        #
        # Don't run a default terminal if background run was chosen
        #
        if [[ "$OPT_UI_GNOME_TERMINAL" = "0" ]]; then
            if [[ "$OPT_RUN_IN_BG" != "" || "$OPT_UI_NO_TERM" -eq 1 ]]; then
                return
            fi
        fi

        log "Launching gnome terminal"

        if [[ "$OPT_TERM_PROFILE" != "" ]]; then
            OPT_TERM="${OPT_TERM}--window-with-profile $OPT_TERM_PROFILE "
        fi

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            if [[ "$OPT_ENABLE_MONITOR" -eq 0 ]]; then
                gnome-terminal --title "${WHICH}"                         \
                    --geometry 100x24                                 \
                    $OPT_TERM                                         \
                    --tab -t "${WHICH}${TTY1_NAME}" -e "/bin/bash $TTY1_CMD" \
                    --tab -t "${WHICH}${TTY2_NAME}" -e "/bin/bash $TTY2_CMD" \
                    --tab -t "${WHICH}${TTY3_NAME}" -e "/bin/bash $TTY3_CMD" \
                    --tab -t "${WHICH}${TTY4_NAME}" -e "/bin/bash $TTY4_CMD" &
            else
                gnome-terminal --title "${WHICH}"                         \
                    --geometry 100x24                                 \
                    $OPT_TERM                                         \
                    --tab -t "${WHICH}${TTY0_NAME}" -e "/bin/bash $TTY0_CMD" \
                    --tab -t "${WHICH}${TTY1_NAME}" -e "/bin/bash $TTY1_CMD" \
                    --tab -t "${WHICH}${TTY2_NAME}" -e "/bin/bash $TTY2_CMD" \
                    --tab -t "${WHICH}${TTY3_NAME}" -e "/bin/bash $TTY3_CMD" \
                    --tab -t "${WHICH}${TTY4_NAME}" -e "/bin/bash $TTY4_CMD" &
            fi
        else
            if [[ "$OPT_ENABLE_MONITOR" -eq 0 ]]; then
                gnome-terminal --title "${WHICH}"                         \
                    --geometry 100x24                                 \
                    $OPT_TERM                                         \
                    --tab -t "${WHICH}${TTY1_NAME}" -e "/bin/bash $TTY1_CMD" \
                    --tab -t "${WHICH}${TTY2_NAME}" -e "/bin/bash $TTY2_CMD" &
            else
                gnome-terminal --title "${WHICH}"                         \
                    --geometry 100x24                                 \
                    $OPT_TERM                                         \
                    --tab -t "${WHICH}${TTY0_NAME}" -e "/bin/bash $TTY0_CMD" \
                    --tab -t "${WHICH}${TTY1_NAME}" -e "/bin/bash $TTY1_CMD" \
                    --tab -t "${WHICH}${TTY2_NAME}" -e "/bin/bash $TTY2_CMD" &
            fi
        fi

        echo $! >> $MY_TERMINALS_PID_FILE
    fi

    if [[ "$OPT_ENABLE_MONITOR" -eq 0 ]]; then
        log_debug "Start QEMU launch..."
        $TTY0_PRE_CMD
        if [[ $? -ne 0 ]]; then
            die "QEMU launch failed"
        fi

        log "QEMU launched"

        I_STARTED_VM=1

        wait_for_qemu_start
        if [[ ! -s $MY_QEMU_PID_FILE ]]; then
            die "QEMU did not start"
        fi
    fi

    if [[ "$OPT_BOOT_VIRSH" != "" ]]; then
        labyrinth 10
        log_debug "Start VIRSH Launch"
        log "VIRSH Launched"

        #
        # Taps/bridges must be tuned post-launch with VIRSH
        #
        tune_taps_and_bridges

        trace virsh list
        trace virsh qemu-monitor-command $DOMAIN_NAME --hmp "info chardev"
    fi

    #
    # Give time for X errors to appear
    #
    sleep 1
}

qemu_start()
{
    if [[ "$OPT_MLOCK" = "1" ]]; then
          add_qemu_cmd "-realtime mlock=on"
    fi

    post_read_options_apply_qemu_options

    if [[ "$OPT_ENABLE_MONITOR" -eq 1 ]]; then
        add_qemu_cmd "-monitor telnet:$TTY_HOST:$QEMU_PORT,server,nowait"
    fi

    #
    # Enable extra serial ports mode.
    #
    if [[ "$OPT_ENABLE_SERIAL_VIRTIO" = "1" ]]; then
#        add_qemu_cmd "-serial telnet:$TTY_HOST:$TTY1_PORT,nowait,server"
        add_qemu_cmd "-device virtio-serial,id=vserial0 -chardev socket,host=$TTY_HOST,port=$TTY1_PORT,telnet,server,nowait,id=vserial0 -device virtconsole,chardev=vserial0"
        add_qemu_cmd "-device virtio-serial,id=vserial1 -chardev socket,host=$TTY_HOST,port=$TTY2_PORT,telnet,server,nowait,id=vserial1 -device virtconsole,chardev=vserial1"

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            add_qemu_cmd "-device virtio-serial,id=vserial2 -chardev socket,host=$TTY_HOST,port=$TTY3_PORT,telnet,server,nowait,id=vserial2 -device virtconsole,chardev=vserial2"
            add_qemu_cmd "-device virtio-serial,id=vserial3 -chardev socket,host=$TTY_HOST,port=$TTY4_PORT,telnet,server,nowait,id=vserial3 -device virtconsole,chardev=vserial3"
        fi
    else
        add_qemu_cmd "-serial telnet:$TTY_HOST:$TTY1_PORT,nowait,server"
        add_qemu_cmd "-serial telnet:$TTY_HOST:$TTY2_PORT,nowait,server"

        if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
            add_qemu_cmd "-serial telnet:$TTY_HOST:$TTY3_PORT,nowait,server"
            add_qemu_cmd "-serial telnet:$TTY_HOST:$TTY4_PORT,nowait,server"
        fi
    fi

    add_qemu_cmd "-boot once=d"

    qemu_generate_cmd `echo $KVM_EXEC $QEMU_CMD | sed 's/sudo //g'`

    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    rm -f $MY_QEMU_PID_FILE &>/dev/null

#
# pidfile leads to too many problems with permissions
#
#            -pidfile $QEMU_PID_FILE \

    qemu_launch $OPT_NODE_NAME $KVM_EXEC $QEMU_CMD

#ifdef CISCO
    #
    # Not used by sunstone. VXR only. Here for reference.
    #

    # eth0 scheme
    # new scheme looks at eth0 encoding for nested or flat information.
    # The format is 00:N/F:CALV:XR:00:00  Where N(4E) is for nested and F(46)
    # is for Flat. For example a flat sim with 1 core for calv and 2 cores for
    #  XR will be mac=00:46:01:02:00:00  For now default is 1 core each

    # eth1 scheme
    # 0[10]:00 LC
    # 02:00 RP
#endif

    #
    # Allow -clean to be able to kill off this process if it goes headless
    #
#    echo $MYPID > $MY_PID_FILE
}

qemu_show_port_info()
{
    #
    # If we did not start QEMU, then return. We may just be creating VMDKs
    # from an existing disk.
    #
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    log "Router logs:"
    log_low " $LOG_DIR"

    #
    # Be careul changing the output format here as other scripts look at
    # this. (joby james)
    #
    log "${TTY1_NAME_LONG} is on port: $TTY1_PORT"
    log "${TTY2_NAME_LONG} is on port: $TTY2_PORT"

    if [[ "$OPT_ENABLE_SER_3_4" = "1" ]]; then
        log "${TTY3_NAME_LONG} is on port: $TTY3_PORT"
        log "${TTY4_NAME_LONG} is on port: $TTY4_PORT"
    fi
    log "${QEMU_NAME_LONG} is on port: $QEMU_PORT"

    #
    # Create a local link to the latest log files
    #
    local SUFFIX=
    if [[ "$OPT_NODE_NAME" != "" ]]; then
        SUFFIX="-$OPT_NODE_NAME"
    fi

    #
    # Do not create symlinks if we did not create any logging
    #
    if [[ "$OPT_UI_LOG" -eq 1 || "$OPT_UI_NO_TERM" -ne 1 ]]; then
        if [[ "$OPT_DISABLE_LOG_SYMLINKS" = "" ]]; then
            ln -sf $LOG_DIR/$TTY0_NAME.log $TTY0_NAME${SUFFIX}.log 2>/dev/null
            ln -sf $LOG_DIR/$TTY1_NAME.log $TTY1_NAME${SUFFIX}.log 2>/dev/null
            ln -sf $LOG_DIR/$TTY2_NAME.log $TTY2_NAME${SUFFIX}.log 2>/dev/null
            ln -sf $LOG_DIR/$TTY3_NAME.log $TTY3_NAME${SUFFIX}.log 2>/dev/null
            ln -sf $LOG_DIR/$TTY4_NAME.log $TTY4_NAME${SUFFIX}.log 2>/dev/null
        fi
    fi
}

#
# Add arguments that will be passed through to QEMU
#
add_qemu_cmd()
{
    log_debug "+ '$*'"

    if [[ "$QEMU_CMD" != "" ]]; then
        QEMU_CMD="$QEMU_CMD $*"
    else
        QEMU_CMD="$1"
    fi
}

add_qemu_pci_cmd()
{
    local bdf="$*"
    local pci_opt=""

    lspci -n | grep -q "$bfd.*Intel Corporation Ethernet Controller XL710 for 40GbE QSFP+.*8086:1583.*rev 01"
    if [[ $? -ne 0 ]]; then
        if [[ "$OPT_DISABLE_FORTVILLE_WORKAROUND" = "" ]]; then
            warn "Adding rombar=0 workaround for Fortville NIC. Use -disable-fortville-workaround if this is not needed"
            pci_opt="${pci_opt},rombar=0"
        fi
    fi

    add_qemu_cmd "-device pci-assign,romfile=,host=${bdf}${pci_opt}"
}

# Set the speed of virtual interfaces in the router.
# These are normally appear as GigabitEthernet.
# -virtspeed 100 means they will appear as HundredGigE
set_virtspeed()
{
    local speed="$1"
    local number='^[0-9]+$'

    # Verify that it is a number
    if [[ ! $speed =~ $number ]]; then
        die "Entered value is incorrect, need to enter a number"
    fi

    VIRTSPEED=$speed
}

# Add a pci bridge definition in the guest for each guest numa node.
# Devices can be attached to these to associate them with a numa node.
# If the do_numa parameter is 1 then each pxb is put on a new numa node;
# otherwise the pxb's are all added to the same/only numa node.
add_numa_pxb()
{
    local num_guest_numa_nodes="$1"
    local do_numa="$2"
    local number='^[0-9]+$'

    # Verify that it is a number
    if [[ ! $num_guest_numa_nodes =~ $number ]]; then
        die "Entered value is incorrect, need to enter a number"
    fi

    NUM_PXBS="$num_guest_numa_nodes"

    # bus numbers must not be consecutive, so use even numbers
    # start numbering at 128 so there is plenty of room for many virual ports
    local bus_nr=128

    # The bus number is also an indication of virtspeed to the dataplane
    # Today 100GE is the only other speed supported.
    if [[ $VIRTSPEED == "100" ]]; then
        bus_nr=230
    elif [[ $VIRTSPEED != "" && $VIRTSPEED != "1" ]]; then
        die "virtual interface speed $VIRTSPEED is not supported"
    fi

    for ((j=0; j<$num_guest_numa_nodes; j+=1)); do
        if [[ "$do_numa" == "1" ]]; then
             numa_opt=",numa_node=$j"
        fi
        add_qemu_cmd "-device pxb,id=pxb_bridge$j,bus=pci.0$numa_opt,bus_nr=$bus_nr,"
        bus_nr=$(( bus_nr + 2 ))
    done
}

# Add a qemu numa hugepage memory device definition for each guest numa node.
# The parameter is a comma-delimited list specifying the amount of hugepage memory
# for each guest node in GB.
#
# Assumes the common case that numa nodes in the guest are the same as the host,
# and that they are numbered starting at 0. For unusual cases you can generate the
# -object lines manually with -passthrough.
#
# The memory can be attached to numa nodes like this:
# -object memory-backend-file,prealloc=yes,mem-path=/mnt/huge,size=12G,policy=bind,host-nodes=0,id=ram-node0
# -object memory-backend-file,prealloc=yes,mem-path=/mnt/huge,size=12G,policy=bind,host-nodes=1,id=ram-node1
# -numa node,nodeid=0,cpus=0-13,memdev=ram-node0
# -numa node,nodeid=1,cpus=14-27,memdev=ram-node1
#
add_numa_memdev()
{
    local mem_list="$1"
    local number='^[0-9]+$'
    local node_num=0
    local hugepage_mnt_point="/mnt/huge"

    local LIST=`echo $mem_list| sed 's/,/ /g'`

    for mem_size in $LIST
    do
        # Verify that it is a number
        if [[ ! $mem_size =~ $number ]]; then
            die "Entered value is incorrect, need to enter a number"
        fi

        cmd="-object memory-backend-file,prealloc=yes,"
        cmd+="mem-path=$hugepage_mnt_point,size=$mem_size"
        cmd+="G,policy=bind,host-nodes=$node_num,id=ram-node$node_num"
        add_qemu_cmd "$cmd"

        node_num=$(( node_num + 1 ))
    done

    # Do not generate the global hugepage options (e.g. -mem-prealloc).
    # Generating both the global and the device options lowers performance.
    OPT_HUGE_PAGES_NO_PREALLOC=1
}

get_device_vendor_id() {
    device="$1"
    len=${#device}
    if [ "$len" -eq 12 ]; then
        device="${device:5:12}"
    fi
    lspci -n | grep "${device}" | cut -d' ' -f3 | sed -r "s/:/ /"
}

bind_pci_to_pci_stub()
{
    local device="$1"

    if [ ! -e "/sys/bus/pci/devices/$device" ]; then
        err "Device $device does not exist to PCI unbind"
        return
    fi

    local device_vendor_id="$(get_device_vendor_id "$device")"

    #
    # Does not seem to be a module on centos
    #
    if [[ "${is_centos}" = "" ]]; then
        lsmod | grep -q pci_stub
        if [[ $? -ne 0 ]]; then
            err "pci_stub is not present on your system, attempting to load it"
            sudo_check_trace modprobe pci_stub
        fi
    fi

    if [ ! -e "/sys/bus/pci/drivers/pci-stub/$device" ]; then
        if [ ! -e "/sys/bus/pci/devices/$device/driver" ]; then
            log "No driver for $device to unbind"
        else
            log_low "+ echo \"$device\" > /sys/bus/pci/devices/$device/driver/unbind"
            echo "$device" > "/sys/bus/pci/devices/$device/driver/unbind"
        fi

        log_low "+ echo \"$device_vendor_id\" > /sys/bus/pci/drivers/pci-stub/new_id"
        echo "$device_vendor_id" > /sys/bus/pci/drivers/pci-stub/new_id
        if [[ $? -ne 0 ]]; then
            if [[ ! -d /sys/bus/pci/drivers/pci-stub ]]; then
                die "The /sys/bus/pci/drivers/pci-stub path does not exist which implies your kernel does not have PCI stub support. Please enable that. I tried to do a modprobe pci_stub but seemingly that failed also"
            fi
        fi
    else
        log "driver for $device is pci_stub already"
    fi
}

add_pci()
{
    local PCI=$1

    # ensure that kvm is configured for passthrough
    allow_unsafe_assigned_int_fordevicepassthru

    #
    # Convert ethX into its PCI number if found
    #
    if [[ $PCI =~ eth.* ]]; then
        ETH_PCI=$(print_nic_info | grep "\<$PCI\>" | awk '{print $1}')
        if [[ "$ETH_PCI" != "" ]]; then
            log "Interface $PCI -> PCI $ETH_PCI"

            if [[ ! -d /sys/bus/pci/devices/$ETH_PCI ]]; then
                if [[ ! -d /sys/bus/pci/devices/0000:$ETH_PCI ]]; then
                    die "PCI device $PCI is not found in /sys/bus/pci/devices/"
                fi
            fi

            PCI=$ETH_PCI
        else
            print_nic_info
            die "$PCI may be unbound already from the system. I cannot map that name to a PCI device. You will need to provide the PCI device ID"
        fi
    fi

    if [[ ! -d /sys/bus/pci/devices/$PCI ]]; then
        if [[ -d /sys/bus/pci/devices/0000:$PCI ]]; then
            PCI="0000:$PCI"
        else
            die "PCI device $PCI is not found in /sys/bus/pci/devices/"
        fi
    fi

    bind_pci_to_pci_stub $PCI

    if [[ "$OPT_PCI_LIST" != "" ]]; then
        OPT_PCI_LIST="$OPT_PCI_LIST $PCI"
    else
        OPT_PCI_LIST="$PCI"
    fi

    log "Will add PCI device $PCI"
}

add_vfiopci()
{
    local PCI=$1

    # ensure that kvm is configured for passthrough
    allow_unsafe_assigned_int_fordevicepassthru

    if [[ ! -d /sys/bus/pci/devices/$PCI ]]; then
        if [[ -d /sys/bus/pci/devices/0000:$PCI ]]; then
            PCI="0000:$PCI"
        else
            die "PCI device $PCI is not found in /sys/bus/pci/devices/"
        fi
    fi

    #this is used to check numa locality - same applies to pci passed via vfio
    # add the device to the list
    if [[ "$OPT_PCI_LIST" != "" ]]; then
        OPT_PCI_LIST="$OPT_PCI_LIST $PCI"
    else
        OPT_PCI_LIST="$PCI"
    fi

    # ok, now the device exists -
    #   bind the device the vfio-pci driver
    #   TBD: Check on group handling - worry about it later...

    #   load the driver (TBD: check if not loaded)
    lsmod | grep -q vfio-pci
    if [[ $? -ne 0 ]]; then
        err "vfio-pci is not present on your system, attempting to load it"
        sudo_check_trace modprobe vfio-pci
    fi

    #   unbind device from the existing driver
    echo $PCI > /sys/bus/pci/devices/$PCI/driver/unbind
    log_low "+    echo $PCI > /sys/bus/pci/devices/$PCI/driver/unbind"

    # get vendor and device id of the device
    vendor=`cat /sys/bus/pci/devices/$PCI/vendor`
    vendor=`echo $vendor  | cut -c 3-`
    device=`cat /sys/bus/pci/devices/$PCI/device`
    device=`echo $device | cut -c 3-`

    log_low "+    echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id"
    echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id

    # just to be safe ..
    log_low "+    echo $PCI > /sys/bus/pci/drivers/vfio-pci/bind"
    echo $PCI > /sys/bus/pci/drivers/vfio-pci/bind

    log "Will add PCI device $PCI"
}

#
# Append arguments to the linux cmdline after root=
#
append_linux_cmd()
{
    #
    # No linux on XRVR
    #
    if [[ "$PLATFORM_NAME" = "IOS-XRVR" ]]; then
        return
    fi

    if [[ "$PLATFORM_NAME" = "Linux" ]]; then
        return
    fi

    log_debug "+ linux '$*'"

    if [[ "$LINUX_CMD_APPEND" != "" ]]; then
        LINUX_CMD_APPEND="$LINUX_CMD_APPEND $*"
    else
        LINUX_CMD_APPEND="$1"
    fi
}

#
# Prepend arguments to the linux cmdline before root=
#
prepend_linux_cmd()
{
    #
    # No linux on XRVR
    #
    if [[ "$PLATFORM_NAME" = "IOS-XRVR" ]]; then
        return
    fi

    if [[ "$PLATFORM_NAME" = "Linux" ]]; then
        return
    fi

    log_debug "+ linux '$*'"

    if [[ "$LINUX_CMD_APPEND" != "" ]]; then
        LINUX_CMD_APPEND="$* $LINUX_CMD_APPEND"
    else
        LINUX_CMD_APPEND="$1"
    fi
}

#
# add the __hugepages=<value> to linux commandline
# sanitize and validate that the number of hugepages is a multiple of 1024
#
add_guest_hugepage()
{
    local guest_hugepage=$1
    local number='^[0-9]+$'

    # Verify that it is a number
    if [[ ! $guest_hugepage =~ $number ]]; then
        die "Entered value is incorrect, need to enter a number"
    fi

    #
    # The VM will allocated either 1G or 2M pages depending on what it
    # can support.
    #
    local mem_requested_kb=$(( $guest_hugepage * 1024 * 2 ))
    local FREE=`free -tm | grep Total | awk '{print $2}'`

    log "Memory check: '${FREE}MB' available memory, requesting '${OPT_PLATFORM_MEMORY_MB}MB'"
    log "VM will use ${mem_requested_kb}Kb of hugepages"

    # Verify that $guest_hugepage is a multiple of 1024
    remainder=`expr $guest_hugepage % 1024`

    if [[ $remainder != 0 ]]; then
         die "Requested hugepages $guest_hugepage is not a multiple of 1024"
    else
         append_linux_cmd "__hugepages=$guest_hugepage"
    fi
}

#
# Remove arguments from the grub cmdline
#
remove_grub_line()
{
    #
    # No linux on XRVR
    #
    if [[ "$PLATFORM_NAME" = "IOS-XRVR" ]]; then
        return
    fi

    log_debug "- grub '$*'"

    if [[ "$GRUB_LINE_REMOVE" != "" ]]; then
        GRUB_LINE_REMOVE="$GRUB_LINE_REMOVE $*"
    else
        GRUB_LINE_REMOVE="$1"
    fi
}

#
# Add arguments from the grub cmdline
#
add_grub_line()
{
    #
    # No linux on XRVR
    #
    if [[ "$PLATFORM_NAME" = "IOS-XRVR" ]]; then
        return
    fi

    log_debug "+ grub '$*'"

    if [[ "$GRUB_LINE_APPEND" != "" ]]; then
        GRUB_LINE_APPEND="$GRUB_LINE_APPEND $*"
    else
        GRUB_LINE_APPEND="$1"
    fi
}

#
# Remove arguments from the linux cmdline
#
remove_linux_cmd()
{
    log_debug "- linux '$*'"

    if [[ "$LINUX_CMD_REMOVE" != "" ]]; then
        LINUX_CMD_REMOVE="$LINUX_CMD_REMOVE $*"
    else
        LINUX_CMD_REMOVE="$1"
    fi
}

print_nic_info()
{
    log "NIC information:"

    python <<%%
#!/usr/bin/python

import subprocess
import re
import pprint

def get_eth_devices():
    "Get all eth names"
    pci_map = []
    dev_pat = '0000:([0-9a-f]{2}:[0-9a-f]{2}\.\d+)\/net\/eth(\d+)'
    proc = subprocess.Popen(('/usr/bin/find',
                             '/sys/devices/',
                             '-name',
                             '*eth*'), stdout=subprocess.PIPE)
    out = proc.stdout.read()
    for line in out.split("\n"):
        isMatch = re.search( r'0000:([0-9a-f]{2}:[0-9a-f]{2}\.\d+)\/net\/(eth\d+)', line)
        if isMatch:
            id = isMatch.groups()[0]
            eth = isMatch.groups()[1]
            str = id + ";" + eth
            pci_map.append(str)
    return pci_map

def get_pci_module( pci_id ):
    "Get pci module name"
    module = ""
    proc = subprocess.Popen(('lspci',
                             '-vv',
                             '-s',
                             pci_id), stdout=subprocess.PIPE)
    out = proc.stdout.read()
    for line in out.split("\n"):
        isMatch = re.search( r'Kernel driver in use:\s+(\S+)', line)
        if isMatch:
            module = isMatch.groups()[0]
    return module

def get_nic_speed( eth_name ):
    "Get NIC speed"
    speed = "Unknown"
    proc = subprocess.Popen(('/sbin/ethtool',
                             eth_name), stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
    out = proc.stdout.read()
    for line in out.split("\n"):
        isMatch = re.search( r'\s+(\d+)baseT/Full', line)
        if isMatch:
            speed = isMatch.groups()[0]
    return speed

print "=" * 40
print "PCI ID\t", "NIC Name\t", "Module\t", "Speed"
print "=" * 40
pci_map = get_eth_devices()
for line in pci_map:
    pci_id = line.split(";")[0]
    eth_name = line.split(";")[1]
    module = get_pci_module (pci_id)
    speed = get_nic_speed( eth_name )
    print pci_id, "\t", eth_name, "\t", module, "\t", speed
%%
}

check_add_all_intel_82599_nics()
{
    if [[ "$OPT_ENABLE_INTEL_82599_NIC_PASSTHROUGH" = "" ]]; then
        return
    fi

    log "Adding intel 82599 interfaces"

    allow_unsafe_assigned_int_fordevicepassthru

    if [[ -z "${is_redhat_family}" ]]; then
        sudo_check_trace rmmod ixgbe
    fi

    local gotone=
    for nic in 82599
    do
        for bdf in $(lspci -vv|egrep -i $nic|awk '{print $1}')
        do
            gotone=1

            add_pci "0000:$bdf"

            add_qemu_pci_cmd 0000:$bdf
        done
    done

    if [[ "$gotone" = "" ]]; then
        err "Could not find any 82599 NICS"
    fi
}

check_add_all_bcm_577_nics()
{
    if [[ "$OPT_ENABLE_BCM_577_NIC_PASSTHROUGH" = "" ]]; then
        return
    fi

    log "Adding BCM 577 interfaces"

    allow_unsafe_assigned_int_fordevicepassthru

    local gotone=
    for nic in BCM577
    do
        for bdf in $(lspci -vv|egrep -i $nic|awk '{print $1}')
        do
            gotone=1

            add_pci "0000:$bdf"

            add_qemu_pci_cmd "0000:$bdf"
        done
    done

    if [[ "$gotone" = "" ]]; then
        err "Could not find any BCM577 NICS"
    fi
}

net_name_truncate_to_fit()
{
    local TRUNCATE=$MAX_TAP_LEN
    local SPACE_NEEDED_FOR_SUFFIX=XXXXX

    while true
    do
        FULLNAME="${OPT_NET_NAME}${OPT_NODE_NAME}${SPACE_NEEDED_FOR_SUFFIX}"
        if [[ ${#FULLNAME} -le $MAX_TAP_LEN ]]; then
            break
        fi

        OPT_NET_NAME=`echo $OPT_NET_NAME | sed 's/\(.*\)./\1/g'`

        if [[ "$OPT_NET_NAME" = "" ]]; then
            die "Either the node name ($OPT_NODE_NAME) or net name ($OPT_NET_NAME) is too long to fit. Linux has a limit of $MAX_TAP_LEN characters and we need space for port numbers also"
        fi
    done
}

read_early_options()
{
    shift
    while [ "$#" -ne 0 ];
    do
        local OPTION=$1

        case $1 in
        -n | -net | --net | -name | --name )
            shift
            OPT_NET_NAME=$1

            if [[ "$1" = "" ]]; then
                help
                die "Expecting argument for $OPTION"
            fi
            ;;

        -node | --node )
            shift
            OPT_NODE_NAME=$1

            if [[ "$1" = "" ]]; then
                help
                die "Expecting argument for $OPTION"
            fi
            ;;

        -w | -workdir | --workdir )
            shift
            OPT_WORK_DIR_HOME=$1
            ;;

        -i | -iso | --iso )
            shift
            OPT_BOOT_ISO=$1

            read_option_sanity_check "$1" "$OPTION"

            case $OPT_BOOT_ISO in
            *vmdk*|*qcow2*)
                die "Please use the -disk option to boot with a preinstalled disk"
                ;;
            esac

            #
            # Some hacks to tell the script to use defaults for IOSXRv
            #
            if [[ $OPT_BOOT_ISO =~ .*iosxrv* ]]; then
                if [[ $OPT_BOOT_ISO =~ .*iosxrv-[-a-z0-9_]*-x64\..* ]]; then
                    # iosxrv-x64
                    init_platform_defaults_iosxrv
                else
                    # iosxrv (classic 32-bit)
                    init_platform_defaults_iosxrv_32
                fi
            fi

#ifdef CISCO
            if [[ $OPT_BOOT_ISO =~ .*n9kv.* ]]; then
                init_platform_defaults_n9kv
            fi
#endif

            if [[ $OPT_BOOT_ISO =~ .*vios.* ]]; then
                init_platform_defaults_iosv
            fi

            if [[ $OPT_BOOT_ISO =~ .*iosv.* ]]; then
                init_platform_defaults_iosv
            fi
            ;;

        -xrvr | --xrvr )
            init_platform_defaults_iosxrv_32
            ;;

        -iosxrv | --iosxrv )
            init_platform_defaults_iosxrv
            ;;

#ifdef CISCO
        -n9kv | --n9kv )
            init_platform_defaults_n9kv
            ;;
#endif

        -iosv | --iosv | -vios | --vios  )
            init_platform_defaults_iosv
            ;;

        -linux | --linux )
            init_platform_defaults_linux
            ;;

        -disk | --disk )
            shift
            OPT_BOOT_DISK=$1

            read_option_sanity_check "$1" "$OPTION"

            case $OPT_BOOT_ISO in
            *iso*)
                die "Please use the -iso option to boot with an ISO"
                ;;
            esac

            #
            # Some hacks to tell the script to use defaults for IOSXRv
            #
            if [[ $OPT_BOOT_DISK =~ .*iosxrv* ]]; then
                if [[ $OPT_BOOT_DISK =~ .*iosxrv-[a-z0-9_]*-x64.* ]]; then
                    # iosxrv-x64
                    init_platform_defaults_iosxrv
                else
                    # iosxrv (classic 32-bit)
                    init_platform_defaults_iosxrv_32
                fi
            fi

#ifdef CISCO
            if [[ $OPT_BOOT_DISK =~ .*n9kv.* ]]; then
                init_platform_defaults_n9kv
            fi
#endif

            if [[ $OPT_BOOT_DISK =~ .*vios.* ]]; then
                init_platform_defaults_iosv
            fi

            if [[ $OPT_BOOT_DISK =~ .*iosv.* ]]; then
                init_platform_defaults_iosv
            fi
            ;;

        -disk2 | --disk2 )
            shift
            OPT_DISK2=$1

            read_option_sanity_check "$1" "$OPTION"
            ;;

        -hw-profile | --hw-profile )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_ENABLE_HW_PROFILE="$1"
            ;;

        -numa | --numa | -numa-pin | --numa-pin )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_NUMA_NODES="$1"
            OPT_MIN_NUMA_NODE=`echo $OPT_NUMA_NODES | cut -f1 -d'-'`
            OPT_MAX_NUMA_NODE=`echo $OPT_NUMA_NODES | cut -f2 -d'-'`
            ;;

#ifdef CISCO
        -strip | --strip )
            cat $0 | sed 's/^/\/\//g' | sed -e 's/^...ifdef/#ifdef/g' -e 's/^...endif/#endif/g' | unifdef -UCISCO -DPROD - | sed 's/^\/\///g'
            exit 0
            ;;
#endif

        -f | -force | --force )
            OPT_FORCE=1
            ;;

        -debug | --debug )
            OPT_DEBUG=1
            ;;

        -v | -version | --version )
            local mod=`cat  $0 | grep " 0.9." | grep -v cat | tail -1 | cut -d" " -f3`
            echo "Version: '$VERSION', last modified by: '$mod'"

            exit 0
            ;;

        -verbose | --verbose )
            OPT_VERBOSE=1

            LOG_PREFIX="$0(pid $MYPID): "
            # enables line numbers in output
            set -x
            PS4='Line ${LINENO}: '
            ;;

        -h | -help | --help )
            help
            exit 0
            ;;

        esac

        shift
    done

    if [[ "$OPT_NODE_NAME" != "" ]]; then
        net_name_truncate_to_fit

        OPT_NODE_NAME="${OPT_NET_NAME}${OPT_NODE_NAME}"
    else
        OPT_NODE_NAME=$OPT_NET_NAME
    fi

    OPT_NET_AND_NODE_NAME=$OPT_NODE_NAME
}

read_option_sanity_check()
{
    local ARG=$1
    local OPTION=$2

    if [[ "$ARG" = "" ]]; then
        help
        die "Expecting argument for $OPTION"
    fi

    #
    # Things that begin with a - are usually options
    #
    if [[ "$ARG" =~ ^\- ]]; then
        help
        die "Missing argument for option $OPTION, error after $LAST_OPTION?"
    fi

    LAST_OPTION=$OPTION
}

read_option_sanity_check_dash_ok()
{
    local ARG=$1
    local OPTION=$2

    if [[ "$ARG" = "" ]]; then
        help
        die "Expecting argument for $OPTION"
    fi

    LAST_OPTION=$OPTION
}

read_options()
{
    shift
    while [ "$#" -ne 0 ];
    do
        local OPTION=$1

        case $OPTION in
        -i | -iso | --iso )
            shift
            OPT_BOOT_ISO=$1

            read_option_sanity_check "$1" "$OPTION"

            case $OPT_BOOT_ISO in
            *vmdk*|*qcow2*)
                die "Please use the -disk option to boot with a preinstalled disk"
                ;;
            esac
            ;;

        -xrvr | --xrvr )
            ;;

        -iosxrv | --iosxrv )
            ;;

#ifdef CISCO
        -n9kv | --n9kv )
            ;;
#endif

        -iosv | --iosv | -vios | --vios  )
            ;;

        -linux | --linux )
            ;;

        -snapshot | --snapshot )
            OPT_SNAPSHOT=",snapshot=on"
            ;;

        -disk-size | --disk-size )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_PLATFORM_DISK_SIZE_GB=$1

            if [[ ! $OPT_PLATFORM_DISK_SIZE_GB =~ .*G ]]; then
                OPT_PLATFORM_DISK_SIZE_GB="${OPT_PLATFORM_DISK_SIZE_GB}G"
            fi

            ;;

        -disk | --disk )
            shift
            OPT_BOOT_DISK=$1

            read_option_sanity_check "$1" "$OPTION"

            case $OPT_BOOT_ISO in
            *iso*)
                die "Please use the -iso option to boot with an ISO"
                ;;
            esac

            if [[ $OPT_BOOT_DISK =~ .*vios.* ]]; then
                init_platform_defaults_iosv
            fi

            if [[ $OPT_BOOT_DISK =~ .*iosv.* ]]; then
                init_platform_defaults_iosv
            fi
            ;;

        -kernel | --kernel )
            shift
            OPT_KERNEL=$1

            read_option_sanity_check "$1" "$OPTION"

            add_qemu_cmd "-kernel $OPT_KERNEL"
            ;;

        -disk2 | --disk2 )
            shift
            OPT_DISK2=$1

            read_option_sanity_check "$1" "$OPTION"
            ;;

        -serial_number | --serial_number  )
            shift
            OPT_SERIAL_NUMBER=$1

            read_option_sanity_check "$1" "$OPTION"
            ;;

        -qcow | --qcow | -qcow2 | --qcow2 )
            OPT_INSTALL_CREATE_QCOW2=1
            ;;

        -export-images | --export-images )
            OPT_EXPORT_IMAGES=1

            if [[ "$2" =~ ^\- ]]; then
                OUTPUT_DIR=.
            else
                shift
                OUTPUT_DIR="$1"

                if [[ "$OUTPUT_DIR" = "" ]]; then
                    OUTPUT_DIR=.
                else
                    #
                    # Check an option is not following
                    #
                    if [[ ! -e $OUTPUT_DIR ]]; then
                        die "Output directory '$1' does not exist"
                    fi
                fi
            fi

            OUTPUT_DIR="$OUTPUT_DIR/"
            OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's/\/\//\//g')

            # No need for consoles if exporting but still log
            OPT_UI_NO_TERM=1
            OPT_UI_LOG=1
            OPT_INSTALL_CREATE_QCOW2=1

            append_linux_cmd "__reboot_on_xr_bake=true"
            ;;

        -ovf | --ovf )
            shift
            OPT_OVF_TEMPLATE=$1

            read_option_sanity_check "$1" "$OPTION"
            ;;

        -boot-virsh | --boot-virsh )
            OPT_BOOT_VIRSH=1
            OPT_ENABLE_TAPS=0
            OPT_INSTALL_CREATE_QCOW2=1
            ;;

        -bootstrap-config | --bootstrap-config | -b | --b )
            shift
            read_option_sanity_check "$1" "$OPTION"
            if [[ ! -f $1 ]]; then
                die "Bootstrap CLI file '$1' does not exist"
            fi

            OPT_BOOTSTRAP_CONFIG_CLI="$1"
            ;;

       -profile-config | --profile-config)  
            shift
            read_option_sanity_check "$1" "$OPTION"
            if [[ ! -f $1 ]]; then
                die "Profile Bootstrap CLI file '$1' does not exist"
            fi

            OPT_PROFILE_CONFIG_CLI="$1"
            ;;

        -topo | --topo | -topology | --topology )
            shift

            read_option_sanity_check "$1" "$OPTION"

            if [[ ! -f "$1" ]]; then
                if [[ "$1" = "b2b" || "$1" = "b2b.topo" ]]; then
                    cat >$1 <<%%
    ####################################################
    #
    # Creates the following topology
    #
    #   +---------+    +---------+
    #   |  node1  |    |  node2  |
    #   +---------+    +---------+
    #     1  2  3        1  2  3
    #     |  |  |        |  |  |
    #     +-----|-[br1]--+  |  |
    #        |  |           |  |
    #        +--|-[br2]-----+  |
    #           |              |
    #           +-[br3]--------+
    #
    ####################################################
    case \$OPT_NET_AND_NODE_NAME in
    *node1*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
        BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
        ;;
    *node2*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
        BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
        ;;
     *)
        die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
        ;;
    esac
%%
#ifdef CISCO
                elif [[ "$1" = "b2b-ha" || "$1" = "b2b-ha.topo" ]]; then
                    cat >$1 <<%%
        #
        # Creates the following topology with a fabric for HA.
        #
        #   +------------------+      +-----------------+
        #   |      node1       |      |      node2      |
        #   |                  |      |                 |
        #   | HostNICs DataNICs|      |HostNICs DataNICs|
        #   +------------------+      +-----------------+
        #     1  2  3  1  2  3         1  2  3  1  2  3
        #        |     |  |  |            |     |  |  |
        #        +--------------[Fab]-----+     |  |  |
        #              |  |  |                  |  |  |
        #              +-----|--[br1]-----------+  |  |
        #                 |  |                     |  |
        #                 +--|--[br2]--------------+  |
        #                    |                        |
        #                    +--[br3]-----------------+
        #
        case \$OPT_NET_AND_NODE_NAME in
        *node1*)
            BRIDGE_HOST_ETH[2]=\${OPT_NET_NAME}Fab
            BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
            BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
            BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
            ;;
        *node2*)
            BRIDGE_HOST_ETH[2]=\${OPT_NET_NAME}Fab
            BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
            BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
            BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
            ;;
         *)
            die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
            ;;
        esac
%%
#endif
                elif [[ "$1" = "chain" || "$1" = "chain.topo" ]]; then
                    cat >$1 <<%%
    ####################################################
    #
    # Creates the following topology
    #
    #   +---------+    +---------+   +---------+
    #   |  node1  |    |  node2  |   |  node3  |
    #   +---------+    +---------+   +---------+
    #     1  2  3        1  2  3       1  2  3
    #     |              |  |          |
    #     +------[br1]---+  +---[br2]--+
    #
    ####################################################
    case \$OPT_NET_AND_NODE_NAME in
    *node1*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        ;;
    *node2*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
        ;;
    *node3*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br2
        ;;
     *)
        die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
        ;;
    esac
%%

                elif [[ "$1" = "long_chain" || "$1" = "longchain.topo" ]]; then
                    cat >$1 <<%%
    ##########################################################
    #
    # Creates the following topology
    #
    #   +---------+    +---------+   +---------+  +---------+
    #   |  node1  |    |  node2  |   |  node3  |  |  node4  |
    #   +---------+    +---------+   +---------+  +---------+
    #     1  2  3        1  2  3       1  2  3      1  2  3
    #     |              |  |             |  |            |
    #     +------[br1]---+  +---[br2]-----+  +--[br3]-----+
    #
    ##########################################################
    case \$OPT_NET_AND_NODE_NAME in
    *node1*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        ;;
    *node2*)
        BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
        BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
        ;;
    *node3*)
        BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
        BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
        ;;
    *node4*)
        BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
        ;;
     *)
        die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
        ;;
    esac
%%

                elif [[ "$1" = "4star" || "$1" = "4star" ]]; then
                    cat >$1 <<%%
   ####################################################
   #
   # Creates the following topology
   #
   #                  +---------+
   #                  |  node2  |
   #                  +---------+
   #                    1  2  3
   #                   /   |   \
   #       ----br1----     |    -br2-
   #      /                |         \
   #     1  2  3           |          1  2  3
   #   +---------+         |        +---------+
   #   |  node1  |        br5       |  node4  |
   #   +---------+         |        +---------+
   #     1  2  3           |          1  2  3
   #         \             |            /
   #          -br3-----    |    -br4----
   #                   \   |   /
   #                    1  2  3
   #                  +---------+
   #                  |  node3  |
   #                  +---------+
   #
   #
   case \$OPT_NET_AND_NODE_NAME in
   *node1*)
       BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
       BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br3
       ;;
   *node2*)
       BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
       BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br5
       BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br2
       ;;
   *node3*)
       BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br3
       BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br5
       BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br4
       ;;
   *node4*)
       BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br2
       BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br4
       ;;
    *)
       die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
       ;;
   esac

echo <<!!!

#
# And sample router configuration for the above
#

!node 1

conf t
 interface GigabitEthernet0/0/0/0
  ipv4 address 10.0.0.1/24
  no shutdown
 interface GigabitEthernet0/0/0/1
  ipv4 address 11.0.0.1/24
  no shutdown
commit

!node 2

conf t
interface GigabitEthernet0/0/0/0
  ipv4 address 10.0.0.2/24
  no shutdown
 interface GigabitEthernet0/0/0/1
  ipv4 address 13.0.0.1/24
  no shutdown
 interface GigabitEthernet0/0/0/2
  ipv4 address 14.0.0.2/24
  no shutdown
commit

!node 3

conf t
 interface GigabitEthernet0/0/0/0
  ipv4 address 11.0.0.2/24
  no shutdown
 interface GigabitEthernet0/0/0/1
  ipv4 address 13.0.0.2/24
  no shutdown
 interface GigabitEthernet0/0/0/2
  ipv4 address 15.0.0.2/24
  no shutdown
commit

!node 4

conf t
 interface GigabitEthernet0/0/0/0
  ipv4 address 14.0.0.1/24
  no shutdown
 interface GigabitEthernet0/0/0/1
  ipv4 address 15.0.0.1/24
  no shutdown
commit

!!!
%%
                elif [[ "$1" = "5star" || "$1" = "5star" ]]; then
                    cat >$1 <<%%
####################################################
#
# Creates the following topology
#
#                  +---------+
#                  |  node2  |
#                  +---------+
#                       1
#                       |
#                      br2
#                       |
#                       3
#   +---------+    +---------+   +---------+
#   |  node1  |    | node5   |   |  node4  |
#   +---------+    +---------+   +---------+
#        1           1  2  4          1
#         \          /  |  \         /
#          -br1------   |   --br4----
#                      br3
#                       |
#                       1
#                  +---------+
#                  |  node3  |
#                  +---------+
#
#
       case \$OPT_NET_AND_NODE_NAME in
       *node1*)
           BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
           ;;
       *node2*)
           BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br2
           ;;
       *node3*)
           BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br3
           ;;
       *node4*)
           BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br4
           ;;
       *node5*)
           BRIDGE_DATA_ETH[1]=\${OPT_NET_NAME}br1
           BRIDGE_DATA_ETH[2]=\${OPT_NET_NAME}br2
           BRIDGE_DATA_ETH[3]=\${OPT_NET_NAME}br3
           BRIDGE_DATA_ETH[4]=\${OPT_NET_NAME}br4
           ;;
        *)
           die "Unhandled node name \$OPT_NET_AND_NODE_NAME"
           ;;
       esac

#                        With sample router config for the above of:
#
# And sample router configuration for the above
#
#                          !node 1
#
#                          conf t
#                           interface GigabitEthernet0/0/0/0
#                            ipv4 address 10.0.0.1/24
#                            no shutdown
#                          commit
#
#                          !node 2
#
#                          conf t
#                          interface GigabitEthernet0/0/0/0
#                            ipv4 address 11.0.0.1/24
#                            no shutdown
#                          commit
#
#                          !node 3
#
#                          conf t
#                           interface GigabitEthernet0/0/0/0
#                            ipv4 address 12.0.0.1/24
#                            no shutdown
#                          commit
#
#                          !node 4
#
#                          conf t
#                           interface GigabitEthernet0/0/0/0
#                            ipv4 address 13.0.0.1/24
#                            no shutdown
#                          commit
#
#                          !node 5
#
#                          conf t
#                           interface GigabitEthernet0/0/0/0
#                            ipv4 address 10.0.0.2/24
#                            no shutdown
#                           interface GigabitEthernet0/0/0/1
#                            ipv4 address 11.0.0.2/24
#                            no shutdown
#                           interface GigabitEthernet0/0/0/2
#                            ipv4 address 12.0.0.2/24
#                            no shutdown
#                           interface GigabitEthernet0/0/0/3
#                            ipv4 address 13.0.0.2/24
#                            no shutdown
#                          commit
%%
                elif [[ "$1" = "mgmt" || "$1" = "mgmt.topo" ]]; then
                    cat >$1 <<%%
    ####################################################
    #
    # Connects the XR management eth to virbr0
    #
    ####################################################
    case \$OPT_NET_AND_NODE_NAME in
    *)
        BRIDGE_HOST_ETH[1]=virbr0
        ;;
    esac
%%
                elif [[ "$1" = "docker-mgmt" || "$1" = "docker-mgmt.topo" ]]; then
                    cat >$1 <<%%

    ####################################################
    #
    # Connects the XR management eth0 and first data to eth1
    #
    ####################################################
    DOCKER_MGMT=xrmgmt
    DOCKER_DATA=xrdata
    case \$OPT_NET_AND_NODE_NAME in
    *)
        BRIDGE_HOST_ETH[1]=\$DOCKER_MGMT
        BRIDGE_HOST_ETH[2]=unused1
        BRIDGE_HOST_ETH[3]=unused2
        BRIDGE_DATA_ETH[1]=\$DOCKER_DATA
        BRIDGE_DATA_ETH[2]=unused3
        BRIDGE_DATA_ETH[3]=unused4
        ;;
    esac

    #
    # Create the bridges if they do not exist
    #
    brctl show | grep -q "\<\$DOCKER_MGMT\>"
    if [[ \$? -ne 0 ]]; then
        brctl addbr \$DOCKER_MGMT
    fi

    brctl show | grep -q "\<\$DOCKER_DATA\>"
    if [[ \$? -ne 0 ]]; then
        brctl addbr \$DOCKER_DATA
    fi

    brctl addif \$DOCKER_MGMT eth0 2>/dev/null
    brctl addif \$DOCKER_DATA eth1 2>/dev/null

    ifconfig \$DOCKER_DATA up
    ifconfig \$DOCKER_MGMT up

    brctl show
%%
                else
                    die "Cannot read topology file, $1"
                fi

                if [[ ! -f "$1" ]]; then
                    die "Cannot read topology file, $1"
                fi

                cat $1
                err "Cannot read topology file: $1"
                err "I have created above ^^^ a template file for you, $1"
                err "Please modify the above file as you see fit."
                sleep 10
            fi

            OPT_TOPO="$OPT_TOPO $1"
            ;;

        -host | --host )
            shift

            read_option_sanity_check "$1" "$OPTION"

            TTY_HOST=$1
            ;;

        -port | --port )
            shift

            read_option_sanity_check "$1" "$OPTION"

            local PORT=$1

            if [[ "$TTY1_PORT" = "" ]]; then
                TTY1_PORT=$PORT
            else
                if [[ "$TTY2_PORT" = "" ]]; then
                    TTY2_PORT=$PORT
                else
                    if [[ "$TTY3_PORT" = "" ]]; then
                        TTY3_PORT=$PORT
                    else
                        if [[ "$TTY4_PORT" = "" ]]; then
                            TTY4_PORT=$PORT
                        else
                            if [[ "$QEMU_PORT" = "" ]]; then
                                QEMU_PORT=$PORT
                            else
                                die "Too many ports specified"
                            fi
                        fi
                    fi
                fi
            fi
            ;;

        -delay | --delay )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_DELAY=$1
            ;;

        -n | -net | --net | -name | --name )
            shift
            ;;

        -node | --node )
            shift
            ;;

        -w | -workdir | --workdir )
            shift
            ;;

        -passthrough | --passthrough )
            shift
            add_qemu_cmd "$1"
            ;;

        -p | -pci | --pci )
            shift

            read_option_sanity_check "$1" "$OPTION"
            add_pci "$1"
            if [[ ( "$2" != "-"* ) && ( "$2" != "" ) ]]; then
                # if next token is not a new option, assume it is the optional socket number
                add_qemu_pci_cmd "$1,bus=pxb_bridge$2"
                shift
            else
                add_qemu_pci_cmd "$1"
            fi
            OPT_PCI_SET=1
            ;;

        -vfiopci | --vfiopci )
            shift

            read_option_sanity_check "$1" "$OPTION"
            add_vfiopci "$1"
            add_qemu_cmd "-device vfio-pci,host=$1"
            OPT_VFIOPCI_SET=1
            ;;

        -clean | --clean )
            OPT_CLEAN=1
            ;;

        -tech-support | --tech-support )
            OPT_TECH_SUPPORT=1
            ;;

#ifdef CISCO
        -sim | --sim )
            OPT_ENABLE_SIM_MODE=1
            err "-sim option is deprecated and will be removed"
            ;;

        -dev | --dev )
            OPT_ENABLE_DEV_MODE=1
            ;;

        -docker | --docker )
            OPT_DOCKER_FEATURE=1
            ;;
#endif

        -vga | --vga )
            OPT_ENABLE_VGA=1

            remove_linux_cmd "console=ttyS0"

            remove_grub_line "serial --unit=0 --speed=115200"
            remove_grub_line "terminal serial"
            ;;

        -vnc| --vnc )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_VNC_SERVER="$1"
            OPT_ENABLE_VGA=1
            ;;

        -cmdline-append | --cmdline-append )
            shift
            append_linux_cmd "$1"
            ;;

        -huge | --huge )
            OPT_HUGE_PAGES_CHECK=1
            ;;

        -cpu | --cpu | -cpu-pin | --cpu-pin | -cpu-list | --cpu-list )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_CPU_LIST="$1"
            ;;

        -numa | --numa | -numa-pin | --numa-pin )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_NUMA_NODES="$1"
            OPT_MIN_NUMA_NODE=`echo $OPT_NUMA_NODES | cut -f1 -d'-'`
            OPT_MAX_NUMA_NODE=`echo $OPT_NUMA_NODES | cut -f2 -d'-'`
            ;;

        -numa-pxb | --numa-pxb)
            shift
            read_option_sanity_check "$1" "$OPTION"
            add_numa_pxb "$1" 1
            ;;

        -pxb | --pxb)
            shift
            read_option_sanity_check "$1" "$OPTION"
            add_numa_pxb "$1" 0
            ;;

        -virtspeed | --virtspeed)
            shift
            read_option_sanity_check "$1" "$OPTION"
            set_virtspeed "$1"
            ;;

        -numa-memdev | --numa-memdev)
            shift
            read_option_sanity_check "$1" "$OPTION"
            OPT_NUMA_MEMDEV="$1"
            ;;

        -guest-hugepages | --guest-hugepages )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_GUEST_HUGEPAGE="$1"
            ;;

        -cmdline-remove | --cmdline-remove )
            shift
            remove_linux_cmd "$1"
            ;;

#ifdef CISCO
        -prod | --prod )
            OPT_ENABLE_DEV_MODE=0
            OPT_ENABLE_SIM_MODE=0
            ;;
#endif
        -hw-profile | --hw-profile )
            shift
            ;;

        -hw-profile-cpu | --hw-profile-cpu )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_ENABLE_HW_PROFILE_CPU="$1"
            ;;

        -hw-profile-vm-mem-gb | --hw-profile-vm-mem-gb )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_ENABLE_HW_PROFILE_VM_MEM_GB="$1"
            ;;

        -hw-profile-packet-mem-mb | --hw-profile-packet-mem-mb )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_ENABLE_HW_PROFILE_PACKET_MEM_MB="$1"
            ;;

        -rx-queues-per-port | --rx-queues-per-port )
            shift

            read_option_sanity_check "$1" "$OPTION"
            OPT_RX_QUEUES_PER_PORT="$1"
            ;;

        -10g | --10g | -10G | --10G | -82599 | --82599 )
            OPT_ENABLE_INTEL_82599_NIC_PASSTHROUGH=1
            ;;

        -disable-fortville-workaround | --disable-fortville-workaround )
            OPT_DISABLE_FORTVILLE_WORKAROUND = 1
            ;;

        -bcm577 | --bcm577 )
            OPT_ENABLE_BCM_577_NIC_PASSTHROUGH=1
            ;;

        -disable-log-symlinks | --disable-log-symlinks )
            OPT_DISABLE_LOG_SYMLINKS=1
            ;;

        -disable-logging | --disable-logging )
            OPT_DISABLE_LOGGING=1
            ;;

        -disable-extra-tty | --disable-extra-tty )
            OPT_ENABLE_SER_3_4=0
            ;;

        -enable-extra-tty | --enable-extra-tty )
            OPT_ENABLE_SER_3_4=1
            ;;

        -disable-kvm | --disable-kvm )
            OPT_ENABLE_KVM=0
            ;;

        #
        # noroot is deprecated
        #
        -noroot | --noroot | -disable-sudo | --disable-sudo )
            SUDO=
            OPT_ENABLE_SUDO=0
            ;;

        -disable-daemonize | --disable-daemonize )
            OPT_ENABLE_DAEMONIZE=0
            ;;

        -disable-monitor | --disable-monitor )
            OPT_ENABLE_MONITOR=0
            ;;

        -disable-smp | --disable-smp )
            OPT_ENABLE_SMP=0
            ;;

        -disable-numa | --disable-numa )
            OPT_ENABLE_NUMA_CHECKING=0
            ;;

        -disable-ksm | --disable-ksm )
            OPT_KSMOFF=1
            ;;

        -m | -memory | --memory | -mem | --mem )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_PLATFORM_MEMORY_MB=$1

            #
            # Convert M and G to machine readable numbers in Mb
            #
            if [[ $OPT_PLATFORM_MEMORY_MB =~ .*M ]]; then
                OPT_PLATFORM_MEMORY_MB=`echo $OPT_PLATFORM_MEMORY_MB | sed 's/M//g'`
            elif [[ $OPT_PLATFORM_MEMORY_MB =~ .*G ]]; then
                OPT_PLATFORM_MEMORY_MB=`echo $OPT_PLATFORM_MEMORY_MB | sed 's/G//g'`
                OPT_PLATFORM_MEMORY_MB=$(( OPT_PLATFORM_MEMORY_MB * 1024))
            else
                OPT_PLATFORM_MEMORY_MB=$(( OPT_PLATFORM_MEMORY_MB * 1024))
            fi

            ;;

        -install-memory | --install-memory | -install-mem | --install-mem )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_INSTALL_MEMORY_MB=$1

            #
            # Convert M and G to machine readable numbers in Mb
            #
            if [[ $OPT_INSTALL_MEMORY_MB =~ .*M ]]; then
                OPT_INSTALL_MEMORY_MB=`echo $OPT_INSTALL_MEMORY_MB | sed 's/M//g'`
            elif [[ $OPT_INSTALL_MEMORY_MB =~ .*G ]]; then
                OPT_INSTALL_MEMORY_MB=`echo $OPT_INSTALL_MEMORY_MB | sed 's/G//g'`
                OPT_INSTALL_MEMORY_MB=$(( OPT_INSTALL_MEMORY_MB * 1024))
            else
                OPT_INSTALL_MEMORY_MB=$(( OPT_INSTALL_MEMORY_MB * 1024))
            fi

            ;;

        -mtu | --mtu )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_MTU=$1
            ;;

        -bios | --bios )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_BIOS=$1
            ;;

        -distributed | --distributed )
            # In the distributed mode, control ethernet (which is of host nic
            # type) is critical for inter-node communication. However, virtio
            # host nic would cause dropping ethernet frame with size > 9K.
            # e1000 is also causing issues, in that its kernel-mode workflow
            # is sub-optimal and can cause significant scheduling issues.
            # Switch back to virtio-net-pci and solve the MTU issue separately.
            if [[ "$OPT_HOST_NIC_TYPE" == "" ]]; then
                NIC_HOST_INTERFACE=virtio-net-pci
                NIC_DATA_INTERFACE=virtio-net-pci
            fi
            append_linux_cmd "__distributed=true"
            ;;

        -boardtype | --boardtype )
            shift

            read_option_sanity_check "$1" "$OPTION"

            if [[ "$1" != "RP" ]]; then
                if [[ "$1" == "LC" ]]; then
                    append_linux_cmd "boardtype=$1"
                    remove_linux_cmd "boardtype=RP"
                else
                    help
                    die "Board type can only be 'RP' or 'LC'"
                fi
            fi
            ;;

        -rack | --rack )
            shift

            read_option_sanity_check "$1" "$OPTION"

            append_linux_cmd "__rack=$1"
            ;;

        -slot | --slot )
            shift

            read_option_sanity_check "$1" "$OPTION"

            append_linux_cmd "__slot=$1"
            ;;

        -txqueuelen | --txqueuelen )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_TXQUEUELEN=$1
            ;;

#ifdef CISCO
        -enable-fabric-nic | --enable-fabric-nic )
            OPT_ENABLE_FABRIC_NIC=1
            ;;

#endif
        -data-nics | --data-nics )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_DATA_NICS=$1
            ;;

        -host-nics | --host-nics )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_HOST_NICS=$1
            ;;

        -host-nic | --host-nic | -host-nic-type | --host-nic-type )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_HOST_NIC_TYPE=$1
            ;;

        -data-nic | --data-nic | -data-nic-type | --data-nic-type )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_DATA_NIC_TYPE=$1
            ;;

        -host-nic-queues | --host-nic-queues )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_HOST_NIC_QUEUES=$1
            ;;

        -data-nic-queues | --data-nic-queues )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_DATA_NIC_QUEUES=$1
            ;;

        -data-nic-csum-offload-disable | --data-nic-csum-offload-disable )
            NIC_DATA_CSUM_OFFLOAD_ENABLE=0
            ;;

        -data-nic-csum-offload-enable | --data-nic-csum-offload-enable )
            #
            # 2 is intentional to force the value on in cli.
            # 1 means use QEMU default.
            #
            NIC_DATA_CSUM_OFFLOAD_ENABLE=2
            ;;

        -host-nic-csum-offload-disable | --host-nic-csum-offload-disable )
            NIC_HOST_CSUM_OFFLOAD_ENABLE=0
            ;;

        -host-nic-csum-offload-enable | --host-nic-csum-offload-enable )
            #
            # 2 is intentional to force the value on in cli.
            # 1 means use QEMU default.
            #
            NIC_HOST_CSUM_OFFLOAD_ENABLE=2
            ;;

        -smp | --smp )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_PLATFORM_SMP="-smp $1"
            ;;

        -disable-runas | --disable-runas )
            OPT_ENABLE_RUNAS=0
            ;;

        -runas | --runas )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_ENABLE_RUNAS=1
            OPT_RUNAS=$1
            ;;

        -disable-network | --disable-network )
            OPT_ENABLE_NETWORK=0
            ;;

        -disable-address-assign | --disable-address-assign )
            OPT_ENABLE_ADDRESS_ASSIGN=0
            ;;

        -disable-snooping | --disable-snooping )
            OPT_ENABLE_SNOOPING=0
            ;;

        -enable-snooping | --enable-snooping )
            OPT_ENABLE_SNOOPING=1
            ;;

        -leave-snooping | --leave-snooping )
            OPT_ENABLE_SNOOPING=2
            ;;

        -disable-querier | --disable-querier )
            OPT_ENABLE_QUERIER=0
            ;;

        -enable-querier | --enable-querier )
            OPT_ENABLE_QUERIER=1
            ;;

        -leave-querier | --leave-querier )
            OPT_ENABLE_QUERIER=2
            ;;

        -enable-lldp | --enable-lldp )
            OPT_ENABLE_LLDP=1
            ;;

        -enable-serial-virtio | --enable-serial-virtio )
            OPT_ENABLE_SERIAL_VIRTIO=1

#            prepend_linux_cmd "console=hvc0"
            append_linux_cmd "console=hvc0"
            append_linux_cmd "hvc_iucv=4"
            remove_linux_cmd "console=ttyS0"
            remove_linux_cmd "quiet"

            remove_grub_line "serial --unit=0 --speed=115200"
            remove_grub_line "terminal serial"
            ;;

        -disable-serial-virtio | --disable-serial-virtio )
            OPT_ENABLE_SERIAL_VIRTIO=0
            ;;

        -enable-disk-virtio | --enable-disk-virtio )
            OPT_ENABLE_DISK_VIRTIO=1
            ;;

        -disable-disk-virtio | --disable-disk-virtio )
            OPT_ENABLE_DISK_VIRTIO=0
            ;;

        -disable-disk-bootstrap-virtio | --disable-disk-bootstrap-virtio )
            OPT_ENABLE_DISK_BOOTSTRAP_VIRTIO=0
            ;;

        -disable-taps | --disable-taps )
            OPT_ENABLE_TAPS=0
            ;;

        -disable-bridges | --disable-bridges )
            OPT_ENABLE_BRIDGES=0
            ;;

        -no-reboot | --no-reboot )
            OPT_ENABLE_EXIT_ON_QEMU_REBOOT=1
            ;;

        -disable-boot | --disable-boot )
            OPT_DISABLE_BOOT=1
            ;;

        -disable-modify-iso | --disable-modify-iso )
            OPT_DISABLE_MODIFY_ISO=1
            ;;

        -generate-xml-only | --generate-xml-only )
            die "To generate VIRSH XML - use -export-images"
            OPT_GENERATE_XML_ONLY=1
            ;;

        -bg | --bg )
            OPT_RUN_IN_BG=1
            ;;

        -kvm | --kvm )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_USER_KVM_EXEC=$1
            ;;

        -tmpdir | --tmpdir )
            shift

            read_option_sanity_check "$1" "$OPTION"

            TMPDIR=$1
            export TMPDIR

            INCLUDE_TMPDIR=1
            ;;

        -qemu-img | --qemu-img )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_USER_QEMU_IMG_EXEC=$1
            ;;

        -wait | --wait )
            # deprecated
            ;;

        -f | -force | --force )
            OPT_FORCE=1
            ;;

        -r | -recreate | --recreate )
            OPT_ENABLE_RECREATE_DISKS=1
            ;;

        -term-bg | --term-bg )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_TERM_BG_COLOR=$1
            ;;

        -term-fg | --term-fg )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_TERM_FG_COLOR=$1
            ;;

        -term-font | --term-font )
            shift

            read_option_sanity_check_dash_ok "$1" "$OPTION"

            OPT_TERM_FONT=$1
            ;;

        -term-profile | --term-profile )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_TERM_PROFILE=$1
            ;;

        -loglevel | --loglevel )
            shift

            read_option_sanity_check "$1" "$OPTION"

            OPT_LOG_LEVEL=$1
            ;;

        -term-opt | --term-opt )
            shift

            read_option_sanity_check_dash_ok "$1" "$OPTION"

            OPT_TERM="$OPT_TERM $1 "
            ;;

        -gnome | --gnome )
            OPT_UI_GNOME_TERMINAL=1
            ;;

        -xterm | --xterm )
            OPT_UI_XTERM=1
            ;;

        -konsole | --konsole )
            OPT_UI_KONSOLE=1
            ;;

        -mrxvt | --mrxvt )
            OPT_UI_MRXVT=1
            ;;

        -screen | --screen )
            OPT_UI_SCREEN=1
            ;;

        -tmux | --tmux )
            OPT_UI_TMUX=1
            ;;

        -noterm | --noterm )
            OPT_UI_NO_TERM=1
            ;;

        -log | --log )
            OPT_UI_LOG=1
            ;;

        -debug | --debug )
            ;;

        -verbose | --verbose )
            ;;

        -mlock | --mlock )
            OPT_MLOCK=1
            ;;

        -sr-iov-bdw | --sr-iov-bdw )
            shift

            if [[ "$1" = "1" ]]; then
              CTX_SRIOV=$1
            fi
            if [[ "$1" = "x" ]]; then
              CTX_SRIOV=$1
            fi
            if [[ "$1" = "40" ]]; then
              CTX_SRIOV=$1
            fi
            ;;

        -sr-iov | --sr-iov )

            if [[ "$CTX_SRIOV" = "1" ]]; then
              CMD_SRIOV="igb"
            else
              CMD_SRIOV="i${CTX_SRIOV}gbe"
            fi
            CMD_SRIOVF="${CMD_SRIOV}vf"

            sudo_check_trace modprobe -r $CMD_SRIOV
            sudo_check_trace modprobe -r pci-stub
            sudo_check_trace modprobe $CMD_SRIOV
            sudo_check_trace modprobe -r $CMD_SRIOVF

            CLEANUP_SRIOV=1
            ;;

        -sr-iov-dep | --sr-iov-dep )
            shift

            if [[ "$CTX_SRIOV" = "1" ]]; then
              CMD_SRIOV="igb"
            else
              CMD_SRIOV="i${CTX_SRIOV}gbe"
            fi
            CMD_SRIOVF="${CMD_SRIOV}vf"

            sudo_check_trace modprobe -r $CMD_SRIOV
            sudo_check_trace modprobe -r pci-stub
            sudo_check_trace modprobe $CMD_SRIOV max_vfs=$1
            sudo_check_trace modprobe -r $CMD_SRIOVF

            CLEANUP_SRIOV=1
            ;;

        -pfif | --pfif )
            shift

            PFIF=$1

            ifconfig $1 up allmulti promisc
            if [[ "$CTX_SRIOV" = "1" ]]; then
              ifconfig $1 mtu 9200
            else
              ifconfig $1 mtu 9700
              ethtool -K $1 ntuple on
            fi
            ;;

        -vfnum | --vfnum )
            shift

            sudo sh << EOF
            echo $1 > /sys/class/net/$PFIF/device/sriov_numvfs
EOF
            for ((j=0; j<$1; j+=1)); do
                ip link set $PFIF vf $j spoofchk off
            done
            ;;

        -vfix | --vfix )
            shift

            VFIX=$1

            ;;

        -vfvl | --vfvl )
            shift

            ip link set $PFIF vf $VFIX vlan $1

            ;;

        -vfrl | --vfrl )
            shift

            ip link set $PFIF vf $VFIX rate $1

            ;;

        -guess_iso | --guess_iso | -g | --g )
            shift
            OPT_GUESS_ISO_TYPE="$1"
            OPT_GUESS_ISO_RELEASE="$2"
            shift
            ;;

        *)
            help
            die "Unknown option $*"
            ;;
        esac

        shift
    done
}

#
# Check that the memory carving fits within the memory being made available
# to QEMU
#
domain_sanity_check_table_cpu()
{
    local resources=$1
    local profile=$2
    local tuple=$3

    local ndomains=${#PLATFORM_LXC_DOMAINS[@]}
    local xr_and_calv_cores=0
    local cp_cores=
    local dp_cores=

    for ((j=0; j<$ndomains; j+=1)); do
        local f=$(( $j + 1 ))
        local field=`echo $tuple | cut -f$f -d'/'`

        if [[ $field =~ .*,.* ]]; then
            cp_cores=`echo $field | cut -f1 -d','`
            dp_cores=`echo $field | cut -f2 -d','`

            cp_min=`echo $cp_cores | cut -f1 -d'-'`
            cp_max=`echo $cp_cores | cut -f2 -d'-'`

            dp_min=`echo $dp_cores | cut -f1 -d'-'`
            dp_max=`echo $dp_cores | cut -f2 -d'-'`

            if [[ "$cp_max" = "" ]]; then
                cp_max=$cp_min
            fi

            if [[ "$dp_max" = "" ]]; then
                dp_max=$dp_min
            fi

            log "Control plane guest cores  : *Guest* CPUS $cp_min .. $cp_max"
            log "Data plane guest cores     : *Guest* CPUS $dp_min .. $dp_max"

            if [[ "$cp_min" = "" ]]; then
                die "Bad control plane minimum core setting: $cp_min in value $tuple"
            fi

            if [[ "$dp_min" = "" ]]; then
                die "Bad dataplane plane minimum core setting: $cp_min in value $tuple"
            fi

            if [[ $cp_min -gt $cp_max ]]; then
                die "Control plane first core $cp_min higher than last core $cp_max in value $tuple"
            fi

            if [[ $dp_min -gt $dp_max ]]; then
                die "Data plane first core $dp_min higher than last core $dp_max in value $tuple"
            fi

            if [[ "$TOTAL_CORES" = "" ]]; then
                get_total_cores
            fi

            if [[ $dp_min -ge $TOTAL_CORES ]]; then
                die "Data plane first core, $dp_min is higher than the number of cores that will be available inside the guest ($TOTAL_CORES). Remember this core range is for the guest. It is not for the host."
            fi

            if [[ $cp_min -ge $TOTAL_CORES ]]; then
                die "Data plane first core, $dp_min is higher than the number of cores that will be available inside the guest ($TOTAL_CORES). Remember this core range is for the guest. It is not for the host."
            fi

            total_cp_cores=$(( $cp_max - $cp_min + 1 ))
            total_dp_cores=$(( $dp_max - $dp_min + 1 ))

            log_debug "Control plane guest cores  : $total_cp_cores"
            log_debug "Data plane guest cores     : $total_dp_cores"

            total_cp_and_dp_cores=$(( $total_cp_cores + $total_dp_cores ))

            log "Total guest cores needed   : $total_cp_and_dp_cores"
            log "Available guest cores      : $resources"

            if [[ $total_cp_and_dp_cores -gt $resources ]]; then
                die "Value $tuple exceeds the number of guest cores available. Asked for $total_cp_and_dp_cores, have $resources"
            fi

            if [[ $total_cp_and_dp_cores -lt $resources ]]; then
                warn "Value $tuple is not using all guest cores available. Asked for $total_cp_and_dp_cores, have $resources"
            fi
        else
            if [[ "$field" = "" ]]; then
                die "Malformed input in value $tuple. Expecting x/y/a-b,c-d format"
            fi

            xr_and_calv_cores=$(( $xr_and_calv_cores + $field ));
        fi
    done

    if [[ ! $field =~ .*,.* ]]; then
        die "Malformed input in value $tuple. Expecting x/y/a-b,c-d format; missing comma"
    fi

    if [[ $xr_and_calv_cores -gt $total_cp_and_dp_cores ]]; then
        die "Value $tuple needs $xr_and_calv_cores guest cores but only $total_cp_and_dp_cores provided"
    fi

    if [[ $xr_and_calv_cores -gt $total_cp_cores ]]; then
        die "Value $tuple needs $xr_and_calv_cores control plane guest cores but only $total_cp_cores are given in the core range $field"
    fi
}

#
# Perform checks on the -hw-profile-cpu value the end user has passed in
#
domains_sanity_check_table_cpu()
{
    local tuple=$1
    local smp=$OPT_PLATFORM_SMP

    if [[ "$OPT_PLATFORM_SMP" = "" ]]; then
        return
    fi

    smp=`echo $OPT_PLATFORM_SMP | sed 's/-smp //g'`

    local cpus=1
    local cores=1
    local threads=1
    local sockets=1

    echo $smp | grep -q cores=
    if [[ $? -eq 0 ]]; then
        cores=`echo $smp | sed 's/.*cores=\([0-9]*\).*/\1/g'`
        if [[ "$cores" = "" ]]; then
            cores=1
        fi
    fi

    echo $smp | grep -q threads=
    if [[ $? -eq 0 ]]; then
        threads=`echo $smp | sed 's/.*threads=\([0-9]*\).*/\1/g'`
        if [[ "$threads" = "" ]]; then
            threads=1
        fi
    fi

    echo $smp | grep -q sockets=
    if [[ $? -eq 0 ]]; then
        sockets=`echo $smp | sed 's/.*sockets=\([0-9]*\).*/\1/g'`
        if [[ "$sockets" = "" ]]; then
            sockets=1
        fi
    fi

    #
    # Handle a simple numeric value also
    #
    case $smp in
        ''|*[!0-9]*) cpus=1 ;;
        *) cpus=$smp ;;
    esac

    local total_cores=$(( $cpus * $cores * $threads * $sockets ));

    log "Total guest cores          : $total_cores ($cpus x $cores x $threads x $sockets)"

    domain_sanity_check_table_cpu $total_cores "$OPT_ENABLE_HW_PROFILE" $tuple
}

#
# Find the total cores available
#
get_total_cores()
{
    if [[ "$OPT_PLATFORM_SMP" = "" ]]; then
        return
    fi

    smp=`echo $OPT_PLATFORM_SMP | sed 's/-smp //g'`

    local cpus=1
    local cores=1
    local threads=1
    local sockets=1

    echo $smp | grep -q cores=
    if [[ $? -eq 0 ]]; then
        cores=`echo $smp | sed 's/.*cores=\([0-9]*\).*/\1/g'`
        if [[ "$cores" = "" ]]; then
            cores=1
        fi
    fi

    echo $smp | grep -q threads=
    if [[ $? -eq 0 ]]; then
        threads=`echo $smp | sed 's/.*threads=\([0-9]*\).*/\1/g'`
        if [[ "$threads" = "" ]]; then
            threads=1
        fi
    fi

    echo $smp | grep -q sockets=
    if [[ $? -eq 0 ]]; then
        sockets=`echo $smp | sed 's/.*sockets=\([0-9]*\).*/\1/g'`
        if [[ "$sockets" = "" ]]; then
            sockets=1
        fi
    fi

    #
    # Handle a simple numeric value also
    #
    case $smp in
        ''|*[!0-9]*) cpus=1 ;;
        *) cpus=$smp ;;
    esac

    local total_cores=$(( $cpus * $cores * $threads * $sockets ));

    log "Total cores requested      : $total_cores ($cpus cpu(s) x $cores core(s) x $threads thread(s) x $sockets socket(s))"

    # Useful for basic profile selection too
    export TOTAL_CORES=$total_cores
}

#
# Check that the CPU carving fits within the cores being made available to QEMU
#
domain_sanity_check_table_mem()
{
    local resources=$1
    local a_profile=$2
    local tuple=$3

    local ndomains=${#PLATFORM_LXC_DOMAINS[@]}
    local total_mem=0

    for ((j=0; j<$ndomains; j+=1)); do
        local f=$(( $j + 1 ))
        local field=`echo $tuple | cut -f$f -d'/'`

        if [[ "$field" = "" ]]; then
            die "Malformed input in value $tuple. Expecting x/y/z format"
        fi

        field=$(echo | awk "{printf(\"%.0f\n\", $field)}")
        total_mem=$(( $total_mem + $field ));
    done

    if [[ $total_mem -lt $resources ]]; then
        warn "Memory required ($total_mem Gb) from value $tuple is less than is being made available to QEMU ($resources Gb)"
    fi

    if [[ $total_mem -gt $resources ]]; then
        if [[ "$OPT_FORCE" = "" ]]; then
            die "Memory required ($total_mem Gb) from value $tuple is more than is being made available to QEMU ($resources Gb)"
        else
            banner "Memory required ($total_mem Gb) from value $tuple is more than is being made available to QEMU ($resources Gb)"
        fi
    fi
}

#
# Perform checks on the -hw-profile-vm-mem-gb value the end user has passed in
#
domains_sanity_check_table_mem()
{
    local tuple=$1

    local mem_gb=$(( $OPT_PLATFORM_MEMORY_MB / 1024 ))

    domain_sanity_check_table_mem $mem_gb "$OPT_ENABLE_HW_PROFILE" $tuple
}

post_read_options_check_sanity_bootstrap_cli()
{
    if [[ "$OPT_BOOTSTRAP_CONFIG_CLI" = "" && "$OPT_PROFILE_CONFIG_CLI" = "" ]]; then
        return
    fi

    #
    # If bootstrap CLI has been entered check if workspace already
    # contains a bootstrap file and that it differs. Only if it differs
    # create a bootstrap CLI ISO
    #
    if [[ "$OPT_BOOTSTRAP_CONFIG_CLI" != "" ]]; then
        local WS_CLI="$WORK_DIR/iosxr_config.txt"
        local CREATE_BOOTSTRAP=1
    else
        local WS_CLI=""
        local CREATE_BOOTSTRAP=""
    fi

    ISO_TMPDIR="$WORK_DIR/TMPISO"
    mkdir -p $ISO_TMPDIR
    if [[ ! -d $ISO_TMPDIR ]]; then
        die "Failed to make working dir, $ISO_TMPDIR $WORK_DIR"
    fi
    
    if [[ -e $WS_CLI ]]; then
        # Workspace contains a previous bootstrap CLI - do the correct thing
        diff -q $OPT_BOOTSTRAP_CONFIG_CLI $WS_CLI >/dev/null
        if [[ $? -eq 0 ]]; then
            # Entered and WS bootstrap CLI are the same, warn user and don't add a bootstrap disk
            log_debug "Bootstrap file '$WS_CLI' exists and is the same as $OPT_BOOTSTRAP_CONFIG_CLI"
            if [[ "$OPT_ENABLE_RECREATE_DISKS" = "" ]]; then
                log "Will not create a new bootstrap disk, use -recreate to create the disk anyway"
                sleep 2
                OPT_BOOTSTRAP_CONFIG_CLI=
                CREATE_BOOTSTRAP=
            else
                log "Detected '-recreate' so will force a new bootstrap disk"
                sleep 2
            fi
        else
            log "Bootstrap file '$WS_CLI' exists and differs from $OPT_BOOTSTRAP_CONFIG_CLI"
            log "Will create a new bootstrap disk"
            sleep 2
            rm -f $WS_CLI
            if [[ $? -ne 0 ]]; then
                die "Could not delete existing bootstrap CLI"
            fi
        fi
    fi

    if [[ "$CREATE_BOOTSTRAP" != "" ]]; then
        # Save the bootstrap CLI file to workspace
        cp $OPT_BOOTSTRAP_CONFIG_CLI "$ISO_TMPDIR/iosxr_config.txt"
        if [[ $? -ne 0 ]]; then
            die "Could not copy $OPT_BOOTSTRAP_CONFIG_CLI to $ISO_TMPDIR"
        fi
        OPT_BOOTSTRAP="$ISO_TMPDIR"
    fi

    if [[ "$OPT_PROFILE_CONFIG_CLI" != "" ]]; then
        # Save the profile config CLI file to workspace
        cp $OPT_PROFILE_CONFIG_CLI "$ISO_TMPDIR/xrv9k.yaml"
        if [[ $? -ne 0 ]]; then
            die "Could not copy $OPT_PROFILE_CONFIG_CLI to $ISO_TMPDIR/"
        fi
        OPT_BOOTSTRAP="$ISO_TMPDIR"

    fi

}

#ifdef CISCO
post_read_options_guess_iso()
{
    #
    # User has entered options like: '-guess_iso xrv64 6.1.1'
    # Attempt to find the correct ISO for this platform and release
    # Very handy for a quick check of the latest or stable throttle code.
    # Currently supports XRv9k and XRv64 and xr-dev latest and 6.1.1.
    #

    if [[ "$OPT_GUESS_ISO_TYPE" == "" ]]; then
        # User did not use --guess_iso
        return
    fi

    if [[ "$OPT_BOOT_ISO" != "" ]]; then
        # User also entered an ISO so don't try to guess
        return
    fi

    if [[ "$OPT_BOOT_DISK" != "" ]]; then
        # User also entered a disk so don't try to guess
        return
    fi

    local IMAGE_TYPE=""

    shopt -s nocasematch
    if [[ "$OPT_GUESS_ISO_RELEASE" == "6.1.1" ]]; then
        if [[ ! -d /auto/prod_weekly_archive3 ]]; then
            die "No access to /auto/prod_weekly_archive3. Either link to it using sshfs or run from a location that has access"
        fi

        if [[ "$OPT_GUESS_ISO_TYPE" =~ "XRv64" ]]; then
            IMAGE_TYPE="iosxrv-x64"
        elif [[ "$OPT_GUESS_ISO_TYPE" =~ "XRv9k" ]]; then
            IMAGE_TYPE="xrv9k"
        else
            die "Supported platforms for guess_iso are 'XRv64' or 'XRv9k'"
        fi

        latest_dir=`ls -dlast /auto/prod_weekly_archive3/bin/* | grep '6.1.1.' | grep 'SIT' | head -n 1| awk '{print $10}'`
        full_path="$latest_dir/$IMAGE_TYPE"
        image_is=`ls $full_path | grep fullk9 | grep '.iso' | grep -v 'vga' | grep -v 'vrr' | grep -v 'dev'`
        full_path_image=$full_path/$image_is
        log "Latest $OPT_GUESS_ISO_TYPE 6.1.1 SIT image is: $full_path_image"
        OPT_BOOT_ISO=$full_path_image
    elif [[ "$OPT_GUESS_ISO_RELEASE" == "latest" ]]; then
        if [[ ! -d /auto/ioxdepot4 ]]; then
            die "No access to /auto/ioxdepot4/. Either link to it using sshfs or run from a location that has access"
        fi

        if [[ "$OPT_GUESS_ISO_TYPE" =~ "XRv64" ]]; then
            IMAGE_TYPE="img-iosxrv"
        elif [[ "$OPT_GUESS_ISO_TYPE" =~ "XRv9k" ]]; then
            IMAGE_TYPE="img-xrv9k"
        else
            die "Supported platforms for guess_iso are 'XRv64' or 'XRv9k'"
        fi

        latest_dir=`ls -dlast /auto/ioxdepot4/xr-dev/all/nightly_image_dir/* | grep "C" | sed -n 1p | awk '{print $10}'`
        full_path="$latest_dir/$IMAGE_TYPE"
        image_is=`ls $full_path | grep fullk9 | grep '.iso' | grep -v 'vga' | grep -v 'vrr' | grep -v 'dev'`
        full_path_image=$full_path/$image_is
        log "Latest $OPT_GUESS_ISO_TYPE xr-dev C Build image is: $full_path_image"
        OPT_BOOT_ISO=$full_path_image
    else
        die "Available ISO's are 'latest' or '6.1.1'"
    fi
    shopt -u nocasematch
}
#endif

find_tmp_dir()
{
    #
    # Exporting images can useup lots of space, so use the workdir that
    # we know has to be large anyway
    #
    USE_TMPDIR=$TMPDIR
    if [[ "$USE_TMPDIR" = "" ]]; then
        USE_TMPDIR=$TEMP
        if [[ "$USE_TMPDIR" = "" ]]; then
            USE_TMPDIR=$TMP
        fi
    fi

    if [[ "$USE_TMPDIR" = "" ]]; then
        USE_TMPDIR=$WORK_DIR/export

        log "TMPDIR/TEMP/TMP not set; using $USE_TMPDIR"

        TMPDIR=$USE_TMPDIR
        export TMPDIR

        TEMP=$USE_TMPDIR
        export TEMP

        TMP=$USE_TMPDIR
        export TMP
    fi

    mkdir -p $TMPDIR
    if [[ $? -ne 0 ]]; then
        err "Failed to create tmpdir $USE_TMPDIR. Exporting may fail. Falling back to default TMPDIR"
        unset TMPDIR
        unset TEMP
        unset TMP
    fi
}

post_read_options_check_sanity()
{
    #
    # Booting from ISO? ISO (-i) entered - check validity.
    #
    if [[ "$OPT_BOOT_ISO" != "" ]]; then
        if [[ ! -f "$OPT_BOOT_ISO" ]]; then
            die "ISO name: $OPT_BOOT_ISO not found"
        fi
    fi

#ifdef CISCO
    #
    # Find an ISO if -guess_iso was entered
    #
    post_read_options_guess_iso
#endif

    #
    # Currently don't support exporting images using virsh XML
    # To make this work, need the background (no terminal) code
    # to work.
    #
    if [[ "$OPT_EXPORT_IMAGES" != "" && "$OPT_BOOT_VIRSH" != "" ]]; then
        die "Using virsh to export images is not supported"
    fi

    #
    # Exporting a OVA? Need an ISO or an existing disk
    #
    if [[ "$OPT_EXPORT_IMAGES" != "" ]]; then
        if [[ ! -e $OPT_BOOT_ISO ]]; then
            # User did not input an ISO. Lets try their workspace to see if there is an ISO
            log "No ISO input or ISO invalid. Searching workspace for previous ISO"
            local NAME=`ls $WORK_DIR | grep $BAKED_SUFFIX | tail -1`
            if [[ -f "$WORK_DIR/$NAME" ]]; then
                log "Found $WORK_DIR/$NAME, using this for exporting"
                OPT_BOOT_ISO=$WORK_DIR/${NAME%$BAKED_SUFFIX}
                cp $WORK_DIR/$NAME $OPT_BOOT_ISO
                if [[ $? -ne 0 ]]; then
                    die "Unable to copy ISO to workspace"
                fi
            else
                die "No workspace ISO found. Either run sunstone or provide an ISO with the -i option to boot against"
                return
            fi
        fi

        OVA=${OPT_BOOT_ISO%.iso}.ova

        # Remove the path from OVA and store the name only
        OVA_NAME=${OVA##*/}

        OPT_ENABLE_EXIT_ON_QEMU_REBOOT=1

        if [[ ! -f $DISK1 ]]; then
            if [[ "$OPT_BOOT_ISO" = "" ]]; then
                if [[ "$DISK1" = "" ]]; then
                    die "You need to specify an OVA or boot disk to boot from for creating VMDKs"
                else
                    die "You need to specify an OVA or boot disk to boot from for creating VMDKs as $DISK1 does not exist"
                fi
            fi
        fi

        if [[ "$OPT_BOOT_ISO" = "" ]]; then
            die "I need an ISO for OVA generation as I read the XR versioning information from it."
        fi

        #
        # If baking is on we want to exit on reboot
        #
        OPT_ENABLE_EXIT_ON_QEMU_REBOOT=1

        #
        # If we have no OVF we will use a template, but it is not advised.
        #
        if [[ "$OPT_OVF_TEMPLATE" = "" ]]; then
            log "No OVF template has been specified. Using default OVF template. Check manually it looks ok."
        else
            if [[ ! -f "$OPT_OVF_TEMPLATE" ]]; then
                die "OFV template $OPT_OVF_TEMPLATE not found"
            fi
        fi
        log "Will boot sunstone, quit and export images to $OUTPUT_DIR"
    fi

    #
    # Booting from a disk?
    #
    if [[ "$OPT_BOOT_DISK" != "" ]]; then
        if [[ ! -f "$OPT_BOOT_DISK" ]]; then
            die "Disk $OPT_BOOT_DISK not found."
        fi
    fi

    #
    # Add a second disk?
    #
    if [[ "$OPT_DISK2" != "" ]]; then
        if [[ ! -f "$OPT_DISK2" ]]; then
            die "Disk $OPT_DISK2 not found."
        fi
    fi

    #
    # Check nic type
    #
    case "$OPT_HOST_NIC_TYPE" in
      e1000)
        NIC_HOST_INTERFACE=$OPT_HOST_NIC_TYPE
      ;;

      *virtio*)
        NIC_HOST_INTERFACE=virtio-net-pci
      ;;

      *vmxnet*)
        NIC_HOST_INTERFACE=vmxnet3
      ;;

      *vhost*)
        NIC_HOST_INTERFACE=vhost-net
      ;;

      *)
        if [[ $OPT_HOST_NIC_TYPE != "" ]]; then
            die "bad host NIC type $OPT_HOST_NIC_TYPE, use e1000 or virtio"
        fi
      ;;
    esac

    case "$OPT_DATA_NIC_TYPE" in
      e1000)
        NIC_DATA_INTERFACE=$OPT_DATA_NIC_TYPE
      ;;

      *virtio*)
        NIC_DATA_INTERFACE=virtio-net-pci
      ;;

      *vmxnet*)
        NIC_DATA_INTERFACE=vmxnet3
      ;;

      *vhost*)
        NIC_DATA_INTERFACE=vhost-net
      ;;

      *)
        if [[ $OPT_DATA_NIC_TYPE != "" ]]; then
            die "bad data NIC type $OPT_DATA_NIC_TYPE, use e1000 or virtio"
        fi
      ;;
    esac

    case "$NIC_HOST_INTERFACE" in
      *e1000*)
        VIRSH_HOST_NIC=e1000
      ;;

      *virtio*)
        VIRSH_HOST_NIC=virtio
      ;;

      *vmxnet*)
        VIRSH_HOST_NIC=vmxnet3
      ;;

      *vhost*)
        VIRSH_HOST_NIC=virtio
      ;;

      *)
        err "NIC $NIC_HOST_INTERFACE is unhandled"
      ;;
    esac

    case "$NIC_DATA_INTERFACE" in
      *e1000*)
        VIRSH_DATA_NIC=e1000
      ;;

      *virtio*)
        VIRSH_DATA_NIC=virtio
      ;;

      *vmxnet*)
        VIRSH_DATA_NIC=vmxnet3
      ;;

      *vhost*)
        VIRSH_DATA_NIC=virtio
      ;;

      *)
        err "NIC $NIC_DATA_INTERFACE is unhandled"
      ;;
    esac

    if [[ $OPT_PCI_SET -eq 1 ]]; then
        if [[ $OPT_ENABLE_INTEL_82599_NIC_PASSTHROUGH -eq 1 ]]; then
            help
            die "-10g/-82599 and -pci are mutually exclusive."
        fi

        if [[ $OPT_ENABLE_BCM_577_NIC_PASSTHROUGH -eq 1 ]]; then
            help
            die "-bcm577 and -pci are mutually exclusive."
        fi
    fi

    if [[ $OPT_VFIOPCI_SET -eq 1 ]]; then
        if [[ $OPT_ENABLE_INTEL_82599_NIC_PASSTHROUGH -eq 1 ]]; then
            help
            die "-10g/-82599 and -pci are mutually exclusive."
        fi

        if [[ $OPT_ENABLE_BCM_577_NIC_PASSTHROUGH -eq 1 ]]; then
            help
            die "-bcm577 and -pci are mutually exclusive."
        fi
    fi

    post_read_options_check_sanity_bootstrap_cli
}

check_hw_profile_settings()
{
    log_debug "Platform SMP               : $OPT_PLATFORM_SMP"
    log_debug "Platform memory            : $OPT_PLATFORM_MEMORY_MB MB"

    if [[ "$OPT_ENABLE_HW_PROFILE_CPU" != "" ]]; then
        log "Guest LXC VM CPU split     : $OPT_ENABLE_HW_PROFILE_CPU"
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_VM_MEM_GB" != "" ]]; then
        log "Guest LXC VM memory split  : $OPT_ENABLE_HW_PROFILE_VM_MEM_GB"
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_CPU" != "" ]]; then
        domains_sanity_check_table_cpu $OPT_ENABLE_HW_PROFILE_CPU
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_VM_MEM_GB" != "" ]]; then
        domains_sanity_check_table_mem $OPT_ENABLE_HW_PROFILE_VM_MEM_GB
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE" != "" ]]; then
        append_linux_cmd "__hw_profile=$OPT_ENABLE_HW_PROFILE"
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_VM_MEM_GB" != "" ]]; then
        append_linux_cmd "__hw_profile_vm_mem_gb=$OPT_ENABLE_HW_PROFILE_VM_MEM_GB"
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_PACKET_MEM_MB" != "" ]]; then
        append_linux_cmd "__hw_profile_packet_mem_mb=$OPT_ENABLE_HW_PROFILE_PACKET_MEM_MB"
    fi

    if [[ "$OPT_ENABLE_HW_PROFILE_CPU" != "" ]]; then
        append_linux_cmd "__hw_profile_cpu=$OPT_ENABLE_HW_PROFILE_CPU"
    fi

    if [[ "$OPT_RX_QUEUES_PER_PORT" != "" ]]; then
        append_linux_cmd "__rx_queues_per_port=$OPT_RX_QUEUES_PER_PORT"
    fi
}

#
# Wait for the exit of the QEMU process. Or if not enabled, fall through
# to the code below for a manual wait.
#
wait_for_qemu_exit()
{
    local WAIT=1

    if [[ "$OPT_RUN_IN_BG" != "" ]]; then
        return
    fi

    # No need to wait to to gather logs unless exporting images
    # And in that case -log is enabled to catch the logs
    if [[ "$OPT_UI_NO_TERM" -eq 1 ]] && [[ $OPT_EXPORT_IMAGES = "" ]]; then
        return
    fi

    if [[ -s $MY_QEMU_PID_FILE ]]; then
        cat $MY_QEMU_PID_FILE &>/dev/null
        if [[ $? -ne 0 ]]; then
            $SUDO cat $MY_QEMU_PID_FILE &>/dev/null
            if [[ $? -ne 0 ]]; then
                err "Could not read qemu pid file, $QEMU_PID_FILE."
                err "Cannot exit on QEMU exit."
                WAIT=0
            fi
        fi
    else
        err "No qemu pid file, $QEMU_PID_FILE."
        err "Cannot exit on QEMU exit."
        WAIT=0
    fi

    if [[ $WAIT -eq 0 ]]; then
        log "Hit ^C to quit"

        #
        # Background sleep so we can kill the main process
        #
        sleep 300000000 &
        local PID=$!
#        echo $PID >> $MY_PID_FILE
        wait $PID
    elif [[ "$OPT_BOOT_VIRSH" != "" ]]; then
        log "Press Ctrl+c to quit and destroy virsh domain '$DOMAIN_NAME'"
        sleep infinity
    else
        #
        # Customer is most likely going to want to see this info lat
        #
        log "Waiting for QEMU to exit."
        qemu_show_port_info

        while true
        do
            PID=`cat $MY_QEMU_PID_FILE &>/dev/null`
            if [[ "$PID" != "" ]]; then
                ps $PID &>/dev/null
                if [[ $? -ne 0 ]]; then
                    log "QEMU exited"
                    I_STARTED_VM=
                    return
                fi
            fi

            PID=`$SUDO cat $MY_QEMU_PID_FILE 2>/dev/null`
            if [[ "$PID" != "" ]]; then
                ps $PID &>/dev/null
                if [[ $? -ne 0 ]]; then
                    log "QEMU exited"
                    I_STARTED_VM=
                    return
                fi
            fi

            sleep 1
        done
    fi
}

find_qemu_pid()
{
    if [[ -s $MY_QEMU_PID_FILE ]]; then
        return
    fi

    local TRIES=0

    #
    # QEMU creates the pid file as root with the -pidfile option, so alas we
    # resort to this hackery to try and find the pid so we can kill it as non
    # root. We give the -runas option to QEMU precisely for this reason.
    #
    log_debug "Find QEMU process..."

    while true
    do
        local gotone=
        local PIDS=

        if [[ "$OPT_ENABLE_TAPS" = "1" ]]; then
            #
            # More reliable to look for tap names
            #
            for i in $(seq 1 1)
            do
                if [[ "${TAP_DATA_ETH[$i]}" = "" ]]; then
                    local PID=`ps awwwwx | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
                    PIDS="$PIDS $PID"
                else
                    local PID=`ps awwwwx | grep ${TAP_DATA_ETH[$i]} | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
                    PIDS="$PIDS $PID"
                fi
            done
        else
            if [[ "$TTY1_PORT" != "" ]]; then
                PIDS=`ps awwwwx | grep $TTY1_PORT | grep $TTY2_PORT | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
            fi
        fi

        for i in $PIDS
        do
            ps $i &>/dev/null
            if [[ $? -eq 0 ]]; then
                if [[ "$OPT_DEBUG" != "" ]]; then
                    ps $i | grep -v COMMAND
                fi
                printf "$i " >> $MY_QEMU_PID_FILE
                gotone=1
            fi
        done

        if [[ "$gotone" != "" ]]; then
            log_debug "QEMU PIDs:"
            log_debug " "`cat $MY_QEMU_PID_FILE`
            break
        fi

        sleep 1

        #
        # If we have started QEMU then keep on waiting, else bail out as we
        # could be just doing a cleanup at start time.
        #
        if [[ "$I_STARTED_VM" = "" ]]; then
            return
        fi

        TRIES=$(expr $TRIES + 1)

        if [[ "$TRIES" -eq 60 ]]; then
            log "QEMU is not starting (1 min)."
        fi

        if [[ "$TRIES" -eq 120 ]]; then
            log "QEMU is still not starting (2 mins)."
        fi

        if [[ "$TRIES" -eq 240 ]]; then
            die "QEMU did not start (4 mins)."
        fi
    done
}

find_qemu_pid_one_shot()
{
    #
    # QEMU creates the pid file as root with the -pidfile option, so alas we
    # resort to this hackery to try and find the pid so we can kill it as non
    # root. We give the -runas option to QEMU precisely for this reason.
    #
    log_debug "Find and stop existing processes for node \"$OPT_NODE_NAME\""

    local gotone=
    local PIDS=

    if [[ "$OPT_ENABLE_TAPS" = "1" ]]; then
        #
        # More reliable to look for tap names
        #
        for i in $(seq 1 1)
        do
            if [[ "${TAP_DATA_ETH[$i]}" = "" ]]; then
                local PID=`ps awwwwx | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
                PIDS="$PIDS $PID"
            else
                local PID=`ps awwwwx | grep ${TAP_DATA_ETH[$i]} | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
                PIDS="$PIDS $PID"
            fi
        done
    else
        if [[ "$TTY1_PORT" != "" ]]; then
            PIDS=`ps awwwwx | grep $TTY1_PORT | grep $TTY2_PORT | grep $OPT_NODE_NAME | grep -v grep | grep -v "\<tee\>" | grep -v "script \-f" | awk '{print $1}'`
        fi
    fi

    for i in $PIDS
    do
        #
        # Don't suicide my own process
        #
        if [[ $! -eq $i ]]; then
            log "Skip killing my owned pid $i"
            continue
        fi

        #
        # Same for this child's parent, is it us?
        #
        local parent=$(ps -p $i -o ppid=)
        if [[ "$parent" != "" ]]; then
            if [[ $! -eq $parent ]]; then
                log "Skip killing my owned pid $i"
                continue
            fi

            local pparent=$(ps -p $parent -o ppid=)
            if [[ $! -eq $pparent ]]; then
                log "Skip killing my child owned pid $i"
                continue
            fi
        fi

        ps $i &>/dev/null
        if [[ $? -eq 0 ]]; then
            if [[ "$OPT_DEBUG" != "" ]]; then
                ps $i | grep -v COMMAND
            fi
            printf "$i " >> $MY_QEMU_PID_FILE
            gotone=1
        fi
    done

    if [[ "$gotone" != "" ]]; then
        log "Existing QEMU PIDs:"
        log_low "  "`cat $MY_QEMU_PID_FILE`
    fi
}

wait_for_qemu_start()
{
    #
    # If we did not start QEMU, then return. We may just be creating VMDKs
    # from an existing disk.
    #
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    find_qemu_pid

    if [[ -s $MY_QEMU_PID_FILE ]]; then
        I_STARTED_VM=1

        if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
            log "QEMU started, pid file:"
            log_low " $MY_QEMU_PID_FILE"
            log_low " "`cat $MY_QEMU_PID_FILE`
        fi
    fi
}

qemu_wait()
{
    #
    # If we did not start QEMU, then return. We may just be creating VMDKs
    # from an existing disk.
    #
    if [[ "$QEMU_SHOULD_START" = "" ]]; then
        return
    fi

    wait_for_qemu_exit
}

# Create OVA, VMDK, RAW and QCOW2 images
# Start with the iso, build the VMDK (stream optimized) cot packages
# into the OVA. From the VMDK, create the RAW and then the QCOW2 images.
#
# The flow is someone complicated and multifarious...
# The user can request exported images with and without entering an ISO image
# to build disks off.
# CASE 1 - User entered an ISO
# 1a. No working directory from previous sunstone boot, no -r or -f, Result: should create disks and images
#   E.g. ./sunstone.sh -i /path/to/ios-xrv9k-mini-x.iso -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export
# 1b. User has created a workspace, repeat 1a, Result: should find a workspace and complain about the need to override
#   E.g. ./sunstone.sh -i /path/to/ios-xrv9k-mini-x.iso -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export
# 1c. As 1b but add --force (-f), Result: shouldn't rebuild disks, but should recreate images
#   E.g. ./sunstone.sh -i /path/to/ios-xrv9k-mini-x.iso -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export -f
# 1d. As 1b but add --recreate (-r), Result: should launch qemu and rebuild
#   E.g. ./sunstone.sh -i /path/to/ios-xrv9k-mini-x.iso -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export -r
#
# CASE: 2. User did not enter an ISO - script has to use ISO from workspace if it exists.
# 2a. No working directory from previous sunstone boot, Result: should fail
#   E.g. ../sunstone.sh -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export
# 2b. User has a workspace, repeat 2a, Result: now should find a workspace and warn the user to force or recreate (as case 1)
#   E.g. ../sunstone.sh -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export
# 2c. As 2a, but add --force (-f), Result: shouldn't rebuild disks, but should recreate images
#   E.g. ../sunstone.sh -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export -f
# 2d. As 2a, but add --recreate (-r), Result: Both the disks and the images are recreated
#   E.g. ../sunstone.sh -net rich -node sun -vga -export-images /ws/rwellum-rtp/sunstone_export -r
create_images()
{
    if [[ "$OPT_EXPORT_IMAGES" = "" ]]; then
        return
    fi

    banner "Creating images"
    warn "To ensure cmdline options, like -prod, -vga or -hw-profile, are baked into the calvados/host cmdlines, use -f flag"

    # Could be here without disks being recreated so set qemu-img path again
    if [[ "$QEMU_IMG_EXEC" = "" ]]; then
        check_qemu_img_install_is_ok
    fi

    # Clean up any unwanted .ovf files
    find $WORK_DIR -name "*.ovf" -type f | xargs rm -f

    # Add vga suffix if vga mode was enabled
    VGA_SUFFIX=
    if [[ "$OPT_ENABLE_VGA" = 1 ]]; then
        VGA_SUFFIX=".vga"
    fi

    # Add vrr suffix if -hw-profile vrr was enabled
    VRR_SUFFIX=
    VRR_OVF_SUFFIX=
    if [[ "$OPT_ENABLE_HW_PROFILE" = "vrr" ]]; then
        VRR_SUFFIX=.vrr
        VRR_OVF_SUFFIX=_vrr
    fi

    # Add dev suffix if -prod was NOT enabled
    DEV_SUFFIX=
    if [[ "$OPT_ENABLE_DEV_MODE" = "1" ]]; then
        DEV_SUFFIX=.dev
    fi

    log "Creating Images: OVA and QCOW2"
    if [[ "$OPT_BOOTSTRAP" != "" ]]; then
        log "Creating Bootstrap CLI ISO"
    fi
    log "Output dir is '$OUTPUT_DIR'"

    which cot &>/dev/null
    if [[ $? -ne 0 ]]; then
        install_package_help cot binary cot
    fi

    log "COT version installed:"
    COT_VERSION=`cot --version 2>&1 | sed -n 1p | sed 's/.*\(version [0-9.]\+\).*/\1/g'`
    log "  $COT_VERSION"

    case "$COT_VERSION" in
        *version\ 1.[012345]*)
            warn "Minimum required COT version is 1.6.0 (you have $COT_VERSION)."
            warn "I will try to upgrade to a supported version."
            install_upgrade_pip 'cot>=1.6.0'
            ;;
    esac

    local OVF_TEMPLATE=${WORK_DIR}template.ovf
    local OUT_OVF=${WORK_DIR}${OVA_NAME%.ova}${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.ovf
    local OUT_OVA=${WORK_DIR}${OVA_NAME%.ova}${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.ova

    # Determine the version string
    local VERSION_FILE=${WORK_DIR}/iso/iso_info.txt
    if [[ ! -s "$VERSION_FILE" ]]; then
        die "$VERSION_FILE not found in iso. Needed for creating OVA."
    fi

    local version_string=`cat $VERSION_FILE | awk '{print $4}' | xargs`

    log_debug "XR version $version_string"

    #
    # Warn if we are using a potentially stale OVF file.
    #
    if [[ "$OPT_OVF_TEMPLATE" = "" ]]; then
        OVF_TEMPLATE=${WORK_DIR}template.ovf

        cat >$OVF_TEMPLATE <<%%
<?xml version='1.0' encoding='utf-8'?>
<!-- XML comments in this template are stripped out at build time -->
<!-- Copyright (c) 2013-2018 by Cisco Systems, Inc. -->
<!-- All rights reserved. -->
<ovf:Envelope xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
              xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
              xmlns:vmw="http://www.vmware.com/schema/ovf"
              xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData">
  <ovf:References>
    <!-- Reference to ${PLATFORM_NAME_WITH_SPACES} disk image will be added at build time -->
  </ovf:References>
  <ovf:DiskSection>
    <ovf:Info>Information about virtual disks</ovf:Info>
    <!-- Disk will be added at build time -->
  </ovf:DiskSection>
  <ovf:NetworkSection>
    <ovf:Info>List of logical networks that NICs can be assigned to</ovf:Info>
    <!-- Networks will be added at build time -->
  </ovf:NetworkSection>
    <!-- Configuration is set by cot to whatever the hardware profile passed -->
    <!-- into suntone.sh is. So no need for profiles. -->
    <!-- <ovf:DeploymentOptionSection> -->
    <!--   <ovf:Info>Configuration Profiles</ovf:Info> -->
    <!--   <ovf:Configuration ovf:default="true" ovf:id="DEFAULT-VPE-8CPU-20GB"> -->
    <!--     <ovf:Label>Default</ovf:Label> -->
    <!--     <ovf:Description>Default hardware profile VPE 8 vCPU, 20 GB RAM, 10 NICs</ovf:Description> -->
    <!--   </ovf:Configuration> -->
    <!-- </ovf:DeploymentOptionSection> -->
  <ovf:VirtualSystem ovf:id="${PLATFORM_OVA_ID}">
    <ovf:Info>${PLATFORM_NAME_WITH_SPACES}${VRR_OVF_SUFFIX} virtual machine</ovf:Info>
    <ovf:Name>${PLATFORM_NAME_WITH_SPACES}${VRR_OVF_SUFFIX}</ovf:Name>
    <ovf:OperatingSystemSection ovf:id="1" vmw:osType="otherGuest64">
      <ovf:Info>Description of the guest operating system</ovf:Info>
      <ovf:Description>${PLATFORM_NAME_WITH_SPACES}${VRR_OVF_SUFFIX}</ovf:Description>
    </ovf:OperatingSystemSection>
    <ovf:VirtualHardwareSection>
      <ovf:Info>Definition of virtual hardware items</ovf:Info>
      <ovf:System>
        <vssd:ElementName>Virtual System Type</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <!-- TODO - the below needs to be updated for Xen, etc. -->
        <vssd:VirtualSystemType>vmx-08 vmx-09 Cisco:Internal:VMCloud-01</vssd:VirtualSystemType>
      </ovf:System>
      <!-- Default CPU allocation -->
      <ovf:Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Virtual CPU</rasd:Description>
        <rasd:ElementName>Virtual CPU</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>8</rasd:VirtualQuantity>
      </ovf:Item>
      <ovf:Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>RAM</rasd:Description>
        <rasd:ElementName>20480 MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>20480</rasd:VirtualQuantity>
      </ovf:Item>
      <ovf:Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>IDE Controller 0</rasd:Description>
        <rasd:ElementName>VirtualIDEController 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </ovf:Item>
      <!-- IDE controllers -->
      <ovf:Item>
        <rasd:Address>1</rasd:Address>
        <rasd:Description>IDE Controller 1</rasd:Description>
        <rasd:ElementName>VirtualIDEController 1</rasd:ElementName>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </ovf:Item>
      <!-- Empty CD-ROM drive. Could add CVAC here - but currently
           passed by .virl file -->
      <ovf:Item ovf:required="false">
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Description>CD-ROM drive for CVAC bootstrap configuration</rasd:Description>
        <rasd:ElementName>CD-ROM drive at IDE 1:0</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:Parent>4</rasd:Parent>
        <rasd:ResourceType>15</rasd:ResourceType>
      </ovf:Item>
      <!-- Serial ports -->
      <ovf:Item ovf:required="false">
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Description>Console Port</rasd:Description>
        <rasd:ElementName>Serial 1</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceType>21</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item ovf:required="false">
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Description>Auxiliary Port</rasd:Description>
        <rasd:ElementName>Serial 2</rasd:ElementName>
        <rasd:InstanceID>7</rasd:InstanceID>
        <rasd:ResourceType>21</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item ovf:required="false">
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Description>Calvados Console Port</rasd:Description>
        <rasd:ElementName>Calvados Console</rasd:ElementName>
        <rasd:InstanceID>8</rasd:InstanceID>
        <rasd:ResourceType>21</rasd:ResourceType>
      </ovf:Item>
      <ovf:Item ovf:required="false">
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Description>HostOS Port</rasd:Description>
        <rasd:ElementName>HostOS Console</rasd:ElementName>
        <rasd:InstanceID>9</rasd:InstanceID>
        <rasd:ResourceType>21</rasd:ResourceType>
      </ovf:Item>
      <!--   Note, ESXi only supports 10 network interfaces. -->
      <!--   This includes MgmtEth, CtrlEth, DevEth plus 7 data NICs -->
      <!--   NICs are added below with COT based on this NIC template: -->
      <ovf:Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Description>NIC representing TEMPLATE</rasd:Description>
        <rasd:ElementName>TEMPLATE</rasd:ElementName>
        <rasd:InstanceID>10</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </ovf:Item>
    </ovf:VirtualHardwareSection>
    <ovf:ProductSection ovf:class="${PLATFORM_OVA_CLASS}" ovf:required="false">
      <ovf:Info>Information about the installed software</ovf:Info>
      <!-- GFM TODO: this makes 'IOS XRv 9000_vrr', ugh!-->
      <ovf:Product>${PLATFORM_NAME_WITH_SPACES}${VRR_OVF_SUFFIX}</ovf:Product>
      <ovf:Vendor>Cisco Systems, Inc.</ovf:Vendor>
      <ovf:Version>$version_string</ovf:Version>
      <ovf:FullVersion>Cisco IOS XR Software for the ${PLATFORM_NAME_WITH_SPACES}, Version $version_string</ovf:FullVersion>
      <ovf:ProductUrl>${PLATFORM_URL}</ovf:ProductUrl>
      <ovf:VendorUrl>http://www.cisco.com</ovf:VendorUrl>
    </ovf:ProductSection>
  </ovf:VirtualSystem>
</ovf:Envelope>
%%
    banner "Check $OUT_OVF to verify validity"
    else
        OVF_TEMPLATE=$OPT_OVF_TEMPLATE
    fi

    mount_iso

    log "Create OVF based on hw profile '$OPT_ENABLE_HW_PROFILE'"

    #
    # Customize the OVF template with the proper version number
    #
    COT_CMD=$WORK_DIR/cot.cmd

    cat >$COT_CMD <<%%
    cot -f edit-product \\
        $OVF_TEMPLATE \\
        -o $OUT_OVF \\
        -v '$version_string' \\
        -V 'Cisco IOS XR Software for the ${PLATFORM_NAME_WITH_SPACES}, Version $version_string' \\
        -u '$PLATFORM_URL' \\
        --product-class '$PLATFORM_OVA_CLASS'
%%
    chmod +x $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Make script runnable failed for $COT_CMD"
    fi

    cat $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Did create of $COT_CMD succeed?"
    fi

    $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "COT create of $OUT_OVF failed"
    fi

    # Keep us from accidentally using the original template instead
    # of the updated OUT_OVF file.
    unset OVF_TEMPLATE

    #
    # Add memory and cores plus NICs and associated networks
    #
    COT_CMD=$WORK_DIR/cot.edit_hardware.cmd

    NIC_TYPE="$NIC_HOST_INTERFACE"
    if [[ "$NIC_HOST_INTERFACE" != "$NIC_DATA_INTERFACE" ]]; then
        NIC_TYPE+=" $NIC_DATA_INTERFACE"
    fi

    # For OVA generation on XRv9k, vCloud Director cannot consume virtio
    # which is default entry, so we need to force this to just E1000 for now.
    if [[ "$PLATFORM_NAME" -eq "IOS-XRv-9000" ]]; then
        NIC_TYPE="e1000"
    fi

    #
    # If we wanted to have the number of NICs calculated dynamically at
    # build time, we could do something like:
    #     NIC_COUNT="$((OPT_HOST_NICS + OPT_DATA_NICS))"
    # However, it's easier for most users if we have some extra NICs that are
    # unused, rather than by default having not enough NICs.
    # ESXi (the most common deployment target for an OVF) supports a maximum
    # of 10 NICs, so we'll just use that value.
    #
    NIC_COUNT=10

    # Cores are really a combo of cpus, cores, threads and sockets
    # In case in the future we add any of the latter three, calculate the
    # total cores so it gets reflected accurately.
    # This is calculated from OPT_PLATFORM_SMP
    get_total_cores

    cat >$COT_CMD <<%%
    cot -f edit-hardware \\
             $OUT_OVF \\
             -m ${OPT_PLATFORM_MEMORY_MB}M \\
             -c $TOTAL_CORES \\
             --nics $NIC_COUNT \\
             --nic-names ${PLATFORM_NIC_NAMES} \\
             --nic-types $NIC_TYPE \\
             --nic-networks $(echo $PLATFORM_NIC_NAMES | sed -e 's#/#_#g') \\
             --network-descriptions ${PLATFORM_NETWORK_DESCS}
%%

    chmod +x $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Make script runnable failed for $COT_CMD"
    fi

    cat $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Did create of $COT_CMD succeed?"
    fi

    $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "COT update of $OUT_OVF failed"
    fi

    #
    # Display output OVF
    #
    log "Display OVF Template"
    cat $OUT_OVF

    log "Add disks to OVF"

    # Use the customized template to create OVAs.
    COT_CMD=$WORK_DIR/cot.add.disk.cmd
    cat >$COT_CMD <<%%
    cot -f add-disk \\
        $DISK1 \\
        $OUT_OVF \\
        --output $OUT_OVA \\
        --type harddisk \\
        --controller ide \\
        --address 0:0 \\
        --name 'Hard Disk at IDE 0:0' \\
        --description 'Primary disk drive'
%%
    chmod +x $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Make script runnable failed for $COT_CMD"
    fi

    cat $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "Did create of $COT_CMD succeed?"
    fi

    $COT_CMD
    if [[ $? -ne 0 ]]; then
        die "COT create of $OUT_OVA failed"
    fi

    log "Created $OUT_OVA"

    # Display OVF info to the user
    cot info --verbose $OUT_OVA

    # Copy baked ISO to export images for Openstack
    # Preserve the $BAKED_SUFFIX to differentiate from the compiled ISO
    # For example Openstack needs the ISO baked with -vga
    local ISO=`ls -rt $WORK_DIR | grep baked | tail -1`
    local ISO_NAME=${ISO%.iso$BAKED_SUFFIX}${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.iso

    # Copy bootstrap.iso if user added a bootstrap CLI
    export BOOTSTRAP_NAME=
    if [[ -e $WORK_DIR/bootstrap.iso && $OPT_BOOTSTRAP_CONFIG_CLI != "" ]]; then
        BOOTSTRAP_NAME=`full_path_name ${WORK_DIR}bootstrap.iso`
        BOOTSTRAP_ORIGINAL_NAME=`basename $OPT_BOOTSTRAP_CONFIG_CLI`
        OUTPUT_BOOTSTRAP_NAME=${ISO%.iso$BAKED_SUFFIX}.bootstrap.$BOOTSTRAP_ORIGINAL_NAME.iso
    fi

    #
    # Generate virsh command line in case it is useful
    #
    VIRSH_XML=${WORK_DIR}${OVA_NAME%.ova}${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.virsh.xml
    create_virsh

    local QCOW2_NAME=${OVA_NAME%.ova}${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.qcow2
    local QCOW2_DEST=${OUTPUT_DIR}${QCOW2_NAME}

    log "Moving images to '$OUTPUT_DIR'"
    cp --sparse=always --no-preserve=mode,ownership $OUT_OVA $OUTPUT_DIR
    # Compress the qcow2 image, put in output dir
    qemu-img convert -c -O qcow2 $DISK1 $QCOW2_DEST

    pushd . >/dev/null
    cd $OUTPUT_DIR
    popd >/dev/null

    # Only copy baked image if we have baked one other than the default vpe
    if [[ "$VRR_SUFFIX" != "" || "$VGA_SUFFIX" != "" || "$DEV_SUFFIX" != "" ]]; then
        cp --no-preserve=mode,ownership $WORK_DIR/$ISO ${OUTPUT_DIR}$ISO_NAME
    fi
    cp --no-preserve=mode,ownership $VIRSH_XML $OUTPUT_DIR

    if [[ "$BOOTSTRAP_NAME" != "" ]]; then
        cp --no-preserve=mode,ownership $BOOTSTRAP_NAME $OUTPUT_DIR/$OUTPUT_BOOTSTRAP_NAME
    fi

    rm $OUT_OVA

    #done with iso tmp directory remove it if we have it
    if [[ -e "${OPT_BOOTSTRAP}" ]]; then
        rm -rf ${OPT_BOOTSTRAP}
    fi
}

huge_pages_mount()
{
    mount | grep -q hugetlbfs
    if [[ $? -eq 1 ]]; then
        local hugepage_mnt_point="/mnt/huge"
        sudo_check_trace mkdir -p $hugepage_mnt_point
        if [[ $? -ne 0 ]]; then
            die "Could not create huge pages mount point $hugepage_mnt_point"
        fi

        sudo_check_trace mount -t hugetlbfs nodev $hugepage_mnt_point
        if [[ $? -ne 0 ]]; then
            die "Could not mount huge pages"
        fi
    fi

    local hugepage_mnt_point=`mount | grep hugetlbfs | tail -1 | awk '{print \$3}'`
    if [[ "$hugepage_mnt_point" = "" ]]; then
        die "Could not find huge pages mount point"
    fi

    log "Hugepages mount: $hugepage_mnt_point"

    # Generate qemu hugepage path parameters

    if [[ "$OPT_NUMA_MEMDEV" = "" ]]; then
        # Do not generate the global hugepage options (e.g. -mem-prealloc)
        # with the numa memdev option.
        # Generating both the global and the device options lowers performance.

        add_qemu_cmd "-mem-prealloc -mem-path $hugepage_mnt_point"

    else
        # Add a qemu numa hugepage memory device definition for each guest numa node.
        # The parameter is a comma-delimited list specifying the amount of hugepage memory
        # for each guest node in GB.
        #
        # Assumes the common case that numa nodes in the guest are the same as the host,
        # and that they are numbered starting at 0. For unusual cases you can generate the
        # -object lines manually with -passthrough.
        #
        # The memory can be attached to numa nodes like this:
        # -object memory-backend-file,prealloc=yes,mem-path=/mnt/huge,size=12G,policy=bind,host-nodes=0,id=ram-node0
        # -object memory-backend-file,prealloc=yes,mem-path=/mnt/huge,size=12G,policy=bind,host-nodes=1,id=ram-node1
        # -numa node,nodeid=0,cpus=0-13,memdev=ram-node0
        # -numa node,nodeid=1,cpus=14-27,memdev=ram-node1

        local number='^[0-9]+$'
        local node_num=0

        local LIST=`echo $OPT_NUMA_MEMDEV| sed 's/,/ /g'`

        for mem_size in $LIST
        do
            # Verify that it is a number
            if [[ ! $mem_size =~ $number ]]; then
                die "Entered memdev value is incorrect, need to enter a number"
            fi

            cmd="-object memory-backend-file,prealloc=yes,"
            cmd+="mem-path=$hugepage_mnt_point,size=$mem_size"
            cmd+="G,policy=bind,host-nodes=$node_num,id=ram-node$node_num"
            add_qemu_cmd "$cmd"

            node_num=$(( node_num + 1 ))
        done
    fi
}

huge_pages_alloc()
{
    if [[ $HUGE_PAGE_NEEDED -ge $HUGE_PAGE_TOTAL ]]; then
        sudo_check_trace sysctl vm.nr_hugepages=$HUGE_PAGE_NEEDED
        if [[ $? -ne 0 ]]; then
            die "Failed to allocate needed huge pages"
        fi
    fi
}

huge_pages_get_size()
{
    HUGE_PAGE_SIZE_KB=`cat /proc/meminfo | grep Hugepagesize | awk '{ print $2 }'`
    if [[ "$HUGE_PAGE_SIZE_KB" = "" ]]; then
        HUGE_PAGE_SIZE_KB=0
    fi

    HUGE_PAGE_SIZE_MB=$(( $HUGE_PAGE_SIZE_KB / 1024 ))
}

huge_pages_get_total()
{
    HUGE_PAGE_TOTAL=`cat /proc/meminfo | grep HugePages_Total | awk '{ print $2 }'`
    if [[ "$HUGE_PAGE_TOTAL" = "" ]]; then
        HUGE_PAGE_TOTAL=0
    fi
}

huge_pages_get_free()
{
    HUGE_PAGE_FREE=`cat /proc/meminfo | grep HugePages_Free | awk '{ print $2 }'`
    if [[ "$HUGE_PAGE_FREE" = "" ]]; then
        HUGE_PAGE_FREE=0
    fi
}

huge_pages_get_needed()
{
    if [[ $HUGE_PAGE_SIZE_KB -eq 0 ]]; then
        die "Could not get huge page size"
    fi

    HUGE_PAGE_NEEDED=$(( $OPT_PLATFORM_MEMORY_MB / $HUGE_PAGE_SIZE_MB ))

    #
    # Seem to need to ask for double to get enough memory for KVM
    #
    log "Huge pages needed, ${OPT_PLATFORM_MEMORY_MB}Mb / ${HUGE_PAGE_SIZE_MB}Mb"
    log "Huge pages needed per NUMA node, $HUGE_PAGE_NEEDED"

    #
    # Note, the customer may have to do something like this to give enough
    # pages to each numa node.
    #
    # echo 20480 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
    # echo 20480 > /sys/devices/system/node/node1/hugepages/hugepages-2048kB/nr_hugepages
    #
    # For now we just multiply the needed pages by the number of nodes and
    # hope the pages are load balanced appropriately.
    #
    numa_node_count

    HUGE_PAGE_NEEDED=$(( $HUGE_PAGE_NEEDED * $NUMA_NODE_COUNT ))

    log "Huge pages needed total $HUGE_PAGE_NEEDED"
}

huge_pages_enable()
{
    huge_pages_mount
    huge_pages_get_size
    huge_pages_get_total
    huge_pages_get_free
    huge_pages_get_needed
    huge_pages_alloc
}

huge_pages_info()
{
    log "Checking for huge page support:"

    # hugepage support info
    grep pse /proc/cpuinfo | uniq >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_low " Hugepages of 2MB are supported"
    fi

    grep pdpe1gb /proc/cpuinfo | uniq >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_low " Hugepages of 1GB are supported"
    fi

    local SAVED_IFS=$IFS
    IFS=$'\n'
        for i in `cat /proc/meminfo | grep -i HugePages`
        do
            log_low " $i"
        done
    IFS=$SAVED_IFS
}

print_system_info()
{
    if [[ "$OPT_DEBUG" = "" ]]; then
        return
    fi

    log_low "Kernel flags:"
    for FLAG in HUGETLB IOMMU
    do
        local SAVED_IFS=$IFS
        IFS=$'\n'
        for i in `grep $FLAG /boot/config-\$(uname -r) 2>/dev/null | grep -v 'not set'`
        do
            log_low " $i"
        done
        IFS=$SAVED_IFS
    done
}

check_huge_pages()
{
    huge_pages_info

    if [[ "$OPT_HUGE_PAGES_CHECK" = "1" ]]; then

        grep -q KVM_HUGEPAGES=0 /etc/default/qemu-kvm
        if [[ $? -eq 0 ]]; then
            banner "Please edit /etc/default/qemu-kvm and set KVM_HUGEPAGES=1, then restart qemu-kvm"
        fi

        huge_pages_enable
    fi
}

check_hyperthreading()
{    #number of sockets on the system - for later use ...
    numphy=`grep "physical id" /proc/cpuinfo | sort -u | wc -l`

    #number of logical cores on system
    numlog=`grep "processor" /proc/cpuinfo | wc -l`

    #total number of cores per node
    numcore=`grep "core id" /proc/cpuinfo | sort -u | wc -l`

    #total number of cores
    numcore=$(($numcore * $numphy))
    #banner "numlog $numlog numcore $numcore numphycpu $numphy"

    if [[ "$numlog" -ne "$numcore" ]]; then
        banner "Warning, hyperthreading is enabled"
    fi
}

#
# The number of NUMA nodes, or 1 if not found
#
numa_node_count()
{
    NUMA_NODE_COUNT=`numactl --hardware | grep available | cut -d' ' -f2`
#    NUMA_NODE_COUNT=`numactl -show 2>/dev/null | grep nodebind | sed 's/.*://g' | awk -F' ' '{print NF; exit}'`
    if [[ "$NUMA_NODE_COUNT" = "" ]]; then
        NUMA_NODE_COUNT=1
    fi
}

#
# This function finds the number of numa nodes on the system
# It finds the cpu numbers on each numa node and writes them to a per numa file
#
numa_build_cpu_map()
{
    numa_node_count

    CPU_NODES=${LOG_DIR}/cpunodes

    #
    # list the cpu and node combination for the system
    #
    # Warning, ubuntu has a bug where the node column is messed up.
    # socket seems safer.
    #
#    lscpu -p=socket,cpu | sort -t, -n -k 1,1 -k 2,2 | grep -v "^#" > $CPU_NODES
#    if [[ $? != 0 ]]; then
#       die "Failed to find the node/cpu combination"
#    fi

    log "NUMA information:"

    local SAVED_IFS=$IFS
    IFS=$'\n'
    for i in `numactl --hardware`
        do
            log_low " $i"
        done
    IFS=$SAVED_IFS

    local i
    local total=`expr $NUMA_NODE_COUNT - 1`

    /bin/rm -f $CPU_NODES
    for i in `seq 0 $total`
    do
        numactl --hardware | \
            grep "node $i cpus:" | \
            sed -e "s/.*cpus: //g" -e "s/ /\n/g" | \
            sed -e "s/^/$i,/g"  >> $CPU_NODES
    done
}

numa_build_node_cpu_map()
{
    local filename="$CPU_NODES"
    local total=`expr $NUMA_NODE_COUNT - 1`

    local i=
    for i in `seq 0 $total`
    do
        while read line
        do
            local node=`echo $line | cut -d',' -f1`
            local cpunum=`echo $line | cut -d',' -f2`

            if [[ $node == $i ]]; then
                if [[ "${CPU_NODE_LIST[$i]}" = "" ]]; then
                    CPU_NODE_LIST[$i]=$cpunum
                else
                    CPU_NODE_LIST[$i]=${CPU_NODE_LIST[$i]}",$cpunum"
                fi
                CPU_TO_NODE[$cpunum]=$node
            fi
        done < $filename
    done

    if [[ "$OPT_NUMA_NODES" = "" ]]; then
        return
    fi

    log "NUMA nodes:"
    for i in `seq 0 $total`
    do
        log_low " Node $i CPUs ${CPU_NODE_LIST[$i]}"
    done

    NUMA_MEM_ALLOC="numactl --membind=$OPT_NUMA_NODES"

    NUMA_CPU_LIST=
    local numa=
    for numa in $(seq $OPT_MIN_NUMA_NODE $OPT_MAX_NUMA_NODE); do
        if [[ "$NUMA_CPU_LIST" != "" ]]; then
            NUMA_CPU_LIST="$NUMA_CPU_LIST,${CPU_NODE_LIST[$numa]}"
        else
            NUMA_CPU_LIST=${CPU_NODE_LIST[$numa]}
        fi
    done
}

#
# Given a set of cpus, verify that they all are within the specified numa node
# range, else errmsg input cpu list of form: 1,2,3,4
#
check_numa_cpu_locality()
{
    local ERROR=0

    if [[ "$OPT_NUMA_NODES" = "" ]]; then
        return
    fi

    if [[ "$NUMA_CPU_LIST" = "" ]]; then
        die "NUMA node $OPT_NUMA_NODE chosen, but no NUMA CPU list found"
        return
    fi

    if [[ "$TOTAL_CORES" = "" ]]; then
        get_total_cores
        if [[ "$TOTAL_CORES" = "" ]]; then
            return
        fi
    fi

    if [[ "$OPT_CPU_LIST" = "" ]]; then
        #
        # If no cpu list was given but we did give a numa core then work
        # out the CPUs to use.
        #
        local numa_cpus=$NUMA_CPU_LIST

        local core=
        for core in $(seq 1 $TOTAL_CORES)
        do
            local cpu=$(echo $NUMA_CPU_LIST | cut -d, -f$core)
            if [[ "$cpu" = "" ]]; then
                die "Ran out of CPUs from specified numa node(s). I need $TOTAL_CORES cores on numa node(s) $OPT_NUMA_NODES, but I only have the following list: $NUMA_CPU_LIST"
            fi

            if [[ "$OPT_CPU_LIST" = "" ]]; then
                OPT_CPU_LIST="$cpu"
            else
                OPT_CPU_LIST="$OPT_CPU_LIST,$cpu"
            fi
        done

        if [[ "$OPT_CPU_LIST" = "" ]]; then
            die "NUMA node(s) $OPT_NUMA_NODES chosen, but no cpus chosen"
        fi

        log "NUMA $OPT_NUMA_NODES chosen CPUs:"
        log_low " $OPT_CPU_LIST"
    fi

    local LIST=`echo $OPT_CPU_LIST | sed 's/,/ /g'`

    for cpu in $LIST
    do
        MY_NUMA_NODE=${CPU_TO_NODE[$cpu]}
        if [[ "$MY_NUMA_NODE" = "" ]]; then
            err "Could not map CPU $cpu to a numa node."
            CPU_TO_NODE[$cpu]="-1"
            ERROR=1
        fi
    done

    for cpu in $LIST
    do
        THIS_NODE=${CPU_TO_NODE[$cpu]}
        if [[ "$THIS_NODE" < $OPT_MIN_NUMA_NODE || "$THIS_NODE" > $OPT_MAX_NUMA_NODE ]]; then
            err "Not all CPUs are within the specified node(s) $OPT_NUMA_NODES"
            for cpu in $LIST
            do
                err " CPU $cpu => node ${CPU_TO_NODE[$cpu]}"
            done
            ERROR=1
            break
        fi
    done

    if [[ $ERROR == 1 ]]; then
        banner "Non optimal CPU list. Performance may suffer."

        if [[ "$OPT_FORCE" = "" ]]; then
            sleep 10
        fi
    else
        log "Host CPU node mapping:"

        NUMA_MEM_ALLOC="numactl --membind=$OPT_NUMA_NODES"

        for cpu in $LIST
        do
            log_low " CPU $cpu => node ${CPU_TO_NODE[$cpu]}"
        done
    fi
}

#
# Check PCI devices we plan to use belong to the specified NUMA node(s)
#
check_numa_pci_locality()
{
    local ERROR=0

    if [[ "$OPT_CPU_LIST" = "" ]]; then
        return
    fi

    if [[ "$OPT_PCI_LIST" = "" ]]; then
        return
    fi

    if [[ "$MY_NUMA_NODE" = "" ]]; then
        return
    fi

    local numa_nodes=
    local min_numa=
    local max_numa=
    if [[ $OPT_NUMA_NODES != "" ]]; then
        numa_nodes=$OPT_NUMA_NODES
        min_numa=$OPT_MIN_NUMA_NODE
        max_numa=$OPT_MAX_NUMA_NODE
    else
        numa_nodes=$MY_NUMA_NODE
        min_numa=$MY_NUMA_NODE
        max_numa=$MY_NUMA_NODE
    fi

    local LIST=`echo $OPT_CPU_LIST | sed 's/,/ /g'`

    for PCI in $OPT_PCI_LIST
    do
        local PCI_NODE=`cat /sys/bus/pci/devices/$PCI/numa_node`

        if [[ "$PCI_NODE" = "" ]]; then
            err "Cannot determine the NUMA node for PCI device at /sys/bus/pci/devices/$PCI"
            continue
        fi

        if [[ "$PCI_NODE" < $min_numa || "$PCI_NODE" > $max_numa ]]; then
            if [[ "$PCI_NODE" = "-1" ]]; then
                warn "PCI device $PCI is not tied to any NUMA node but CPUs are using node(s) $numa_nodes"
            else
                err "PCI device $PCI is on NUMA node $PCI_NODE whereas CPUs are using NUMA node(s) $numa_nodes"
                ERROR=1
            fi
        fi
    done

    if [[ $ERROR == 1 ]]; then
        err "Non optimal NUMA PCI configuration. Performance may suffer."

        if [[ "$OPT_FORCE" = "" ]]; then
            sleep 10
        fi
    else
        log "PCI devices are all on the NUMA node(s) $numa_nodes"

        for PCI in $OPT_PCI_LIST
        do
            local PCI_NODE=`cat /sys/bus/pci/devices/$PCI/numa_node`

            log_low " PCI $PCI => node $PCI_NODE"
        done
    fi
}

check_numa_locality()
{
    if [[ $OPT_ENABLE_NUMA_CHECKING -eq 0 ]]; then
        return
    fi

    for i in taskset lscpu numactl
    do
        which $i &>/dev/null
        if [[ $? -ne 0 ]]; then
            warn "Cannot enable NUMA, $i not found"
            true
            return
        fi
    done

    numa_build_cpu_map
    numa_build_node_cpu_map
    check_numa_cpu_locality
    check_numa_pci_locality
}

#
# do various host optimization configs here
#
function check_set_host_config()
{
    # disable ksm if set
    if [[ "$OPT_KSMOFF" = "1" ]]; then
        sudo_check echo 0 > /sys/kernel/mm/ksm/run
        log_low "+ echo 0 > /sys/kernel/mm/ksm/run"

        grep -q KSM_ENABLED=1 /etc/default/qemu-kvm
        if [[ $? -eq 0 ]]; then
            banner "Please edit /etc/default/qemu-kvm and set KSM_ENABLED=0, then restart qemu-kvm"
        fi
    fi
}

init_linux_release_specific()
{
    #
    # One of the Redhat family?
    #
    if [[ -f "/etc/issue.net" ]]; then
        is_centos=$(egrep "CentOS" /etc/issue.net)
        if [[ -n "${is_centos}" ]]; then
            NO_SCRIPT=",script=no,downscript=no"

            uname_r=$(uname -r|egrep '^3\.1[4-9]+')
#ifdef CISCO
            if [[ -z "${uname_r}" ]]; then
                echo "This script need to run on CentOS with kernel 3.14 or higher"
                echo "Your kernel is `uname -r`"
                exit 1
            fi
#endif

            SUDO=
            is_redhat_family=1
        fi

        is_fedora=$(egrep "Fedora" /etc/issue.net)
        if [[ -n "${is_fedora}" ]]; then
            NO_SCRIPT=",script=no,downscript=no"
            SUDO=
            is_redhat_family=1
        fi

        is_redhat=$(egrep "Red Hat" /etc/issue.net)
        if [[ -n "${is_redhat}" ]]; then
            NO_SCRIPT=",script=no,downscript=no"
            SUDO=
            is_redhat_family=1
        fi

        #
        # Red Hat / CEL 7?
        #
        lsb_release -a 2>/dev/null | grep -q RedHat
        if [[ $? -eq 0 ]]; then
            NO_SCRIPT=",script=no,downscript=no"
            SUDO=
            is_redhat=1
            is_redhat7=1
            is_redhat_family=1
        fi
    fi

    #
    # Ubuntu?
    #
    lsb_release -a 2>/dev/null | grep -q Ubuntu
    if [[ $? -eq 0 ]]; then
        SUDO="sudo"
        is_ubuntu=1
    fi
}

init_paths()
{
    export PATH="/sbin:/usr/sbin:$PATH"

#ifdef CISCO
    #
    # Hard coded path for COT.
    #
    # Or get it from https://github.com/glennmatthews/cot
    #
    export PATH="$PATH:/auto/nsstg-tools/bin"
#endif

    #
    # Get rid of any ancient cisco tools sitting on the path
    #
    export PATH=`echo "$PATH" | sed 's;/router/bin;;g'`
}

init_globals()
{
    #
    # Docker startup does not set LOGNAME
    #
    if [[ "$LOGNAME" = "" ]]; then
        LOGNAME=`logname 2>/dev/null`
        if [[ "$LOGNAME" = "" ]]; then
            log_debug "Could not get LOGNAME, assuming root"
            LOGNAME="root"
        fi
    fi

    PWD=`pwd`

    #
    # Python saves centos/redhat/... information
    #
    which python &>/dev/null
    if [[ $? -eq 0 ]]; then
        HOST_PLATFORM=`python -mplatform`
    fi

    if [[ "$HOST_PLATFORM" = "" ]]; then
        HOST_PLATFORM=`uname -a`
    fi

    #
    # For telnet sessions
    #
    RANDOM_PORT_RANGE=10000
    RANDOM_PORT_BASE=10000
    #
    # For doing numa memory binding to a specific node
    #
    NUMA_MEM_ALLOC=""

    #
    # Names used in taps. Can be overriden per platform.
    #
    OPT_DATA_TAP_NAME=Xr
    OPT_HOST_TAP_NAME=Lx
}

lock_assert()
{
    LOCK_FILE=/tmp/$PROGRAM.lock
    HAVE_LOCK_FILE=

    local TRIES=0

    while [ $TRIES -lt 30 ]
    do
        TRIES=$(expr $TRIES + 1)

        if [[ -f $LOCK_FILE ]]; then
            warn "Waiting on lock, $LOCK_FILE"
            sleep 1
            continue
        fi

        echo $MYPID > $LOCK_FILE
        if [[ $? -ne 0 ]]; then
            log "Could not write to lock file, $LOCK_FILE"
            sleep 1
            continue
        fi

        #
        # Make sure anyone else can remove the lockfile if needed
        #
        chmod aog+w $LOCK_FILE 2>/dev/null

        local LOCK_PID=`cat $LOCK_FILE 2>/dev/null`
        if [[ $? -ne 0 ]]; then
            log "Could not read lock file, $LOCK_FILE"
            sleep 1
            continue
        fi

        if [[ "$LOCK_PID" != "$MYPID" ]]; then
            log "Lock file grabbed by PID $LOCK_PID"
            sleep 1
            continue
        fi

        log_debug "Grabbed lock"
        HAVE_LOCK_FILE=$LOCK_FILE
        break
    done

    if [[ "$HAVE_LOCK_FILE" = "" ]]; then
        err "Could not grab lock"
    fi
}

lock_release()
{
    if [[ "$HAVE_LOCK_FILE" = "" ]]; then
        #
        # In case we grabbed the lock but died shortly before setting
        # HAVE_LOCK_FILE, check if our pid is in there.
        #
        if [[ -f $LOCK_FILE ]]; then
            local LOCK_PID=`cat $LOCK_FILE 2>/dev/null`
            if [[ $? -ne 0 ]]; then
                return
            fi

            if [[ "$LOCK_PID" != "$MYPID" ]]; then
                return
            fi

            HAVE_LOCK_FILE=1
        fi
    fi

    if [[ "$HAVE_LOCK_FILE" = "" ]]; then
        return
    fi

    rm -f $HAVE_LOCK_FILE
    HAVE_LOCK_FILE=

    log_debug "Released lock"
}

virsh_start()
{
    if [[ "$OPT_BOOT_VIRSH" = "" ]]; then
        return
    fi

    #
    # Create the virsh xml, die if not successful
    #
    VIRSH_XML=${WORK_DIR}running${VRR_SUFFIX}${VGA_SUFFIX}${DEV_SUFFIX}.virsh.xml

    create_virsh

    if [[ "$VIRSH_VALIDATED" != "valid" ]]; then
        warn "Virsh did not validate, please check xml output and log above."
        warn "Will launch; desired behavior may not be as expected."
    fi
}

#
# do nothing plugins
#
plugin_enable_debugging()
{
    return
}

plugin_warning()
{
    return
}

traceability()
{
    local tracing=$1
    local append=$1.tmp

    grep -q "Plugin script" $1
    if [[ $? -eq 0 ]]; then
        return
    fi

    DATE=`date`

    cat >$append <<%%

Plugin script created by $LOGNAME at $DATE

%%
    uname -a >> $append
    cat /proc/cpuinfo >> $append
    ifconfig -a >> $append

    cat $append | sed 's/^/# /g' >> $tracing
    /bin/rm $append
}

#ifdef CISCO
#
# Look in common locations for sunstone plugin to source
#
source_plugins()
{
    local plugin=sunstone-cisco-private-plugin.sh

    local_plugin=$WORK_DIR/$plugin

    if [[ -f $local_plugin ]]; then
        log_debug "Sourcing cached plugin"
        source $local_plugin
        traceability $local_plugin
        return
    fi

    for plugin_dir in \
        . \
        $WORK_DIR \
        /auto/nsstg-tools/bin/ \
        /auto/nsstg-tools-hard/bin/ \
        /ws/edge2/ \
        /ws/nmcgill-sjc/sunstone/sunstone-pi/ \

    do
        if [[ ! -d $plugin_dir ]]; then
            continue
        fi

        source_plugin=$plugin_dir/$plugin
        if [[ -f $source_plugin ]]; then
            #
            # Copy the file locally to avoid this hit of looking at NFS
            # everytime
            #
            if [[ ! -f $plugin ]]; then
                cp $source_plugin $plugin
                traceability $plugin
            fi

            if [[ ! -f $local_plugin ]]; then
                cp $source_plugin $local_plugin
                traceability $local_plugin
            fi

            log_debug "Sourcing $source_plugin"
            source $source_plugin
            return
        fi
    done
}
#endif

system_info()
{
    log "Version : $VERSION"
    log "PWD     : $PWD"
    local HOST=`hostname`
    log "User    : $LOGNAME@${HOST}"
    log "Host    : $HOST_PLATFORM"
    log "Logs    : $LOG_DIR"
    log "Work dir: $WORK_DIR"

    if [[ "$is_redhat" != "" ]]; then
        log "OS      : Red Hat"
    fi

    if [[ "$is_centos" != "" ]]; then
        log "OS      : Centos"
    fi

    if [[ "$is_ubuntu" != "" ]]; then
        log "OS      : Ubuntu"
    fi

    if [[ "$is_fedora" != "" ]]; then
        log "OS      : Fedora"
    fi
}

main()
{
    init_paths
    init_globals
    init_linux_release_specific
    init_tool_defaults

    read_early_options $0 "$@"
    create_log_dir
    system_info

    #
    # Once we've read the early default options, check our hardware profile
    # which can then be overriden with memory and cpu settings
    #
    if [[ "$PLATFORM_NAME" = "" ]]; then
        init_platform_defaults_ios_xrv_9000
    fi
    init_platform_hw_profile

    read_options $0 "$@"
    create_uuid

#ifdef CISCO
    source_plugins
#endif

    check_shell_is_ok
    check_export_no_kvm
    check_set_host_config

    #
    # Needs to be before topo sourcing in case we modify the networking
    # that apt-get depends on
    #
    check_net_tools_installed

    post_read_options_check_sanity
    post_read_options_init
    post_read_options_fini
    find_tmp_dir

    print_system_info

    check_host_bridge_is_ok
    check_sudo_access
    check_qemu_install_is_ok
    check_redhat_family_install_is_ok
    check_kvm_accel
    check_hyperthreading
    check_hw_profile_settings
    check_huge_pages

    print_nic_info
    check_add_all_intel_82599_nics
    check_add_all_bcm_577_nics
    check_numa_locality

    #
    # Needed earlier for VIOS boot disk create
    #
    lock_assert
    create_disks
    add_non_boot_disks

    if [[ "$OPT_DISABLE_BOOT" != "" ]]; then
        log "QEMU boot disabled"
        lock_release
    else
        create_bridge
        create_taps
        create_telnet_ports
        qemu_create_scripts
        virsh_start
        qemu_start
        lock_release

#ifdef CISCO
        plugin_warning
#endif
        qemu_wait
    fi

    create_images
}

main "$@"

okexit
