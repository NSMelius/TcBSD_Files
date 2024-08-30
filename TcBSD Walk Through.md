****

### Set a static IP Address

ip addresses are usually assigned during start up. To set a static ip address, editing the rc.d file will tell BSD to use the parameters assigned for the network interface chosen.

`doas ee /etc/rc.conf`

There should already be a line beginning with "ifconfig" add the following line to the file. Change "nic" to the desired interface, and the desired IP address in place of `<ipaddress>`
`ifconfig_nic="inet <ipaddress> netmask 255.255.255.0"`
edit the line `dhcpcd_flags="--waitip"` to
`dhcpcd_flags="--denyinterfaces nic"`

press escape then choose a for close and a again to save.

to have the static ip be applied, restart the dhcp client and the network interface service:
`doas service netif restart && doas service dhcpcd restart`

an output with the interfaces listed and the static IP applied should display shortly after.

### Installing TF1200

Next is the installation of the TF1200 UI Client. First, it needs to be installed via the Package Manager. the package manager works very similarly to the 4026 TcPkgManager.

`doas pkg install TF1200-UI-Client`

However, this just downloads the scripts neceassry for set up. to fully install the UI client, the setup scritps need to be run. They can be found in the TwinCAT Functions folder: /usr/local/etc/TwinCAT/Functions/TF1200-UI-Client/scripts.

There are a few scripts here, but only setup-full.sh is needed. the set up needs a few parameters: a user name for the user that will own/launch the client on startup, the setting to autostart the client on start up, and the setting to auto log on to the provided user. THe user does not need to already exist, the scripts will create a new user.

DO NOT use the Administrator account for this.

the call for the full setup looks like:
`doas /usr/local/etc/TwinCAT/Functions/TF1200-UI-Client/scripts/setup-full.sh --user=HMI --autologin --autostart`

This will set up the client to auto start and auto log on to the HMI user. It will also create a new user directory in home where the server configuration files will be stored. if a reboot is performed now, the Ui client will load, but not display anything. 

​To have the client display a website, the config file needs to be edited. to open it:

`doas ee /home/HMI/.config/TF1200-UI-Client/config.json`

look for the section for the web browser and add the following lines:

```json
"startUrl": "https://localhost/config"
"enablekioskmode": true
```
### Mounting a USB Drive

mounting a usb drive does not take much to perform. First  a directory to place the files within the file system is needed. For this create a new directory named usb in the /mnt/ directory:
`doas mkdir /mnt/usb/`

Then mounting the usb drive is a single call. For this to work, the usb must be formatted as FAT32, NTFS will not work. when mounting the drive, the filesystem type must be provided, the device name drive, and the place where the files are to be mounted to:
`doas mount -t msdosfs /dev/da0s1 /mnt/usb/`

### Setting Up Automount

Performing a mount every time could get repetetive, so there is also the option of setting up an automount service in Tc/BSD. This requires a few file edits before the services should be started.

First edit /etc/auto_master

`doas ee /etc/auto_master`

line 8 of this file will be commented out. delete the '#'  to uncomment it.

escape leave and save the file.

Next, edit devd.conf: 

`doas ee /etc/devd.conf`

find the end of the file. It will be labelled as such before a long series of comments. add the following there:

```
notify 100 {
    match   "system"    "GEOM";
    match   "subsystem" "DEV";
    action  "/usr/sbin/automount -c";
};
```

Now the automount service will be able to run and it can be enabled at start up. instead of editing the rc.d file directly, there's another command to have it done without an editor:

`doas sysrc autofs_enable="YES"`

To start the service now, the following can be called

```
doas service automount start
doas service automountd start
doas service autounmountd start
doas service devd restart

```



## Working with Bhyve

### Set up

To create a VM, there a few components that need to be created first:

1) a disk image file to act as the hard drive of the VM.
2) a virtual NIC port to give the VM access to the network and internet.
3) download of an installation media
4) new rules for the firewall to allow the VM to communicate
5) A way to display the VM: Either VNC, or GPU Passthru

### Creating a disk image

First step is to create a new directory in the Administrator's home directory for the VM. 

`doas mkdir -p vms/debian`

There will be a new "vms" folder containing a folder named "debian" in the current directory. Now there is a spot for all of the important files for the VM can go. 

Using WinSCP, copy the debian-vm.sh file to the debian directory. 

Next, the VM will need storage. To create the space, the ZFS can be utilized an a new volume can be created.

`doas zfs create -sV 10G -o volmode=dev "zroot/debian-vm_disk0"`



### Networking

The VM will need an internet connection to install properly. Without it, some features will not be functional. There are a couple different ways to give the VM this connection: Passing through a NIC port using PCI passthru, creating a VLAN, or creating a bridged connection. For this lab, the creation of a bridge interface will suffice.

The interface can be created in two ways using the ifconfig command or adding the interface to the startup command list in /etc/rc.conf. Adding the command to rc.d is preferable, because it means the bridge will be created on every boot. Open /etc/rc.d using a text editor:

`doas ee /etc/rc.conf`

add the following line to the file:

`cloned_interfaces="bridge0"`
After saving, the netif needs to create the interface. This is normally done on startup, but it can be done manually by call:
'doas service netif restart && doas service dhcpcd restart'
Make sure to call this on the Tc/BSD computer itself, as trying to call it over SSH will fail when the second command needs the Administrator password.

It is also possible to add a virtual interface called a tap device in the same way, but that will be handled by the VM script later.

Next, the package filter, Tc/BSD's firewall service needs to be configured to allow communication on the port, as well as opening the port for VNC.

Open /etc/pf.conf.d/bhf in a text editor:

`doas ee /etc/pf.conf.d/bhf`


add the following lines:
```sh
pass in quick on bridge0
pass in quick proto tcp to port 5900

pass in quick proto tcp to port 48898
```
Then, have the packet filter read and enforce the new rules:
`doas pfctl -f /etc/pf.conf.d/bhf`

No output from that command is a good thing.

Now, the system needs to allow virtual interfaces to connect when created. That is done by setting a system variable:

`doas sysctl net.link.tap.up_on_open=1`

and allow communication over the bridge interface to the virtual adapter.

`doas sysctl net.link.bridge.pfil_member=0`

### Final Steps

Finally, the installation media for the VM's OS needs to be downloaded before the first run of the VM
```doas fetch -o "$HOME/vms/debian-installer.iso" https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.6.0-amd64-netinst.iso```

Once finished run the vm script:

```cd /home/Administrator/vms/debian```

``doas sh debian-vm.sh``
``doas sh debian-vm.sh run --install``







