#!/bin/sh

export ZPOOL_VDEV_NAME_PATH=1

ERROR_EXIT() {
    if [ "$#" -eq 2 ]
    then
    local MESSAGE="$1"
    local CODE="$2"
    elif [ "$#" -eq 1 ]
    then
	local MESSAGE="$1"
	local CODE=1
    else
	echo "ERROR: calling ERROR_EXIT incorrectly!" >&2
	exit 1
    fi

    echo "ERROR: $MESSAGE" >&2
    exit $CODE
}

init_apt() {
    cat >> /etc/apt/apt.conf.d/norecommends <<EOF
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
EOF
}

init_network() {
    if [ ! "$#" -eq 0 ]
    then
	ERROR_EXIT "called init_network with $# args: $@"
    fi

    cat > /etc/network/interfaces.d/lo <<EOF
auto lo
iface lo inet loopback
EOF

    for dev in $(ls /sys/class/net | grep -E 'en[a-z0-9]+')
    do
	cat > /etc/network/interfaces.d/$dev <<EOF
auto $dev
iface $dev inet dhcp
EOF
    done
}

configure_locale() {
    if [ $# -eq 1 ]
    then
	local LOCALE=$1
    else
	ERROR_EXIT "called init_locales with $# args: $@"
    fi

    apt install -y locales
    sed -ire "s/# \($LOCALE .*\)$/\1/" /etc/locale.gen
    locale-gen
}

configure_timezone() {
    if [ $# -eq 1 ]
    then
	local TIMEZONE=$1
    else
	ERROR_EXIT "called configure_timezone with $# args: $@"
    fi

    DEBIAN_FRONTEND=noninteractive apt install -y tzdata
    ZONEFILE="/usr/share/zoneinfo/$TIMEZONE"

    if [ -e $ZONEFILE ]
    then
	ln -sf $ZONEFILE /etc/localtime
	dpkg-reconfigure -f noninteractive tzdata
    else
	ERROR_EXIT "/usr/share/zoneinfo/$TIMEZONE does not exist!"
    fi
}

configure_keyboard() {
    if [ $# -eq 2 ]
    then
	local KEYMAP=$1
	local OPTIONS=$2
    else
	ERROR_EXIT "called configure_keyboard with $# args: $@"
    fi

    DEBIAN_FRONTEND=noninteractive apt install -y console-setup

    local LAYOUT=$(echo $KEYMAP|cut -d : -f1)
    local VARIANT=$(echo $KEYMAP|cut -d : -f2)
    cat >> /etc/default/keyboard <<EOF
XKBLAYOUT="$LAYOUT"
XKBVARIANT="$VARIANT"
XKBOPTIONS="$OPTIONS"
XKBMODEL="pc105"
BACKSPACE="guess"
EOF

    setupcon

    echo "Verifying keyboard layout..."
    read -p 'Please type "Hello#123" here: ' kltest
    if [ $kltest != "Hello#123" ]
    then
	echo "FAILED!!!"
	echo "Falling back to configuring keyboard manually..."
	dpkg-reconfigure keyboard-configuration
    fi
}

debian_version() {
    if [ -e /etc/debian_version ]
    then
	cat /etc/debian_version | sed -e 's;^\([0-9][0-9]*\)\..*$;\1;'
    else
	echo 0
    fi
}

install_zfs() {
    if [ $# -eq 0 ]
    then
	local RELEASE="$(debian_version)"
    else
	ERROR_EXIT "called install_zfs with $# args: $@"
    fi

    if [ $RELEASE -eq 8 ]
    then
	cat /etc/apt/sources.list | grep -E '^deb.* jessie main$' | sed -e 's/jessie main$/jessie-backports main contrib/' > /etc/apt/sources.list.d/backports.list
	apt update
	apt install -y -t jessie-backports zfs-dkms zfs-initramfs
	modprobe zfs
    elif [ $RELEASE -eq 10 ]
    then
	cat /etc/apt/sources.list | grep -E '^deb.* buster main$' | sed -e 's/buster main$/buster-backports main contrib/' > /etc/apt/sources.list.d/backports.list
	apt update
	apt install -y -t buster-backports zfs-dkms zfs-initramfs
	modprobe zfs
    elif [ $RELEASE -ge 9 ]
    then
	sed -ire 's/ ([^ ]+) main$/ \1 main contrib/' /etc/apt/sources.list
	apt update
	apt install -y zfs-dkms zfs-initramfs
	modprobe zfs
    else
	ERROR_EXIT "Debian version $RELEASE is not supported!"
    fi
}

init_sudouser() {
    if [ $# -eq 1 -a $(echo $1|grep -E "^[a-zA-Z][a-zA-Z0-9]{2,18}$") ]
    then
	local SUDOUSER=$1
    else
	ERROR_EXIT "called init_sudouser with $# args: $@"
    fi

    apt install -y sudo
    useradd -m -G sudo $SUDOUSER -s /bin/bash
    passwd $SUDOUSER
    passwd -l root
    usermod -s /sbin/nologin root
}

install_kernel_zfs() {
    if [ $# -eq 1 ]
    then
	local ARCH="$1"
	local RELEASE="$(debian_version)"
    else
	ERROR_EXIT "called install_kernel_zfs with $# args: $@"
    fi

    if [ $RELEASE -eq 8 ]
    then
	apt install -y -t jessie-backports linux-image-$ARCH
    elif [ $RELEASE -eq 10 ]
    then
	apt install -y -t buster-backports linux-image-$ARCH
    elif [ $RELEASE -ge 9 ]
    then
	apt install -y linux-image-$ARCH
    else
	ERROR_EXIT "Debian version $RELEASE is not supported!"
    fi
}

configure_grub() {
    if [ $# -eq 2 ]
    then
	local GRUB_MODULES="$1"
	local ZPOOL="$2"
    else
	ERROR_EXIT "called configure_grub with $# args: $@"
    fi

    cat >> /etc/default/grub <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_TERMINAL="console"
GRUB_PRELOAD_MODULES="$(echo $GRUB_MODULES|tr ',' ' ')"
EOF

    if echo $GRUB_MODULES | grep -qw cryptodisk
    then
	cat >> /etc/default/grub <<EOF
GRUB_CRYPTODISK_ENABLE=y
EOF
    fi

    if [ ! -z $ZPOOL ]
    then
	cat >> /etc/default/grub <<EOF
GRUB_CMDLINE_LINUX=root=ZFS=$ZPOOL/$ROOTFS
EOF
    fi
}

install_grub() {
    if [ $# -eq 4 ]
    then
	local BOOTDEV="$1"
	local UEFIBOOT="$2"
	local ARCH="$3"
	local GRUB_MODULES="$4"
    elif [ $# -eq 6 ]
    then
	local BOOTDEV="$1"
	local UEFIBOOT="$2"
	local ARCH="$3"
	local GRUB_MODULES="$4"
	local ZPOOL="$5"
	local ROOTFS="$6"
    else
	ERROR_EXIT "called install_grub with $# arguments: $@"
    fi

    if [ $UEFIBOOT -eq 1 ]
    then
	DEBIAN_FRONTEND=noninteractive apt install -y grub-efi xz-utils
	configure_grub "$GRUB_MODULES" "$ZPOOL"
	grub-install \
	    --target=x86_64-efi \
	    --efi-directory=/boot/efi \
	    --bootloader-id=debian \
	    --compress=xz \
	    --recheck \
	    $BOOTDEV
    else
	DEBIAN_FRONTEND=noninteractive apt install -y grub-pc
	configure_grub "$GRUB_MODULES" "$ZPOOL"
	grub-install $BOOTDEV
    fi

    update-grub

    if [ ! -z "$ZPOOL" ]
    then
	if ! ls /boot/grub/*/zfs.mod 2>&1 > /dev/null
	then
	    ERROR_EXIT "failed to install ZFS module for GRUB!"
	fi
    fi
}

# SOURCING INHERITED DEFAULTS
[ -e /CONFIG_VARS.sh ] && . /CONFIG_VARS.sh

# DEFAULTS
LOCALE="${LOCALE:-en_US.UTF-8}"
TIMEZONE="${TIMEZONE:-Europe/London}"
KEYMAP="${KEYMAP:-us:dvorak}"
XKBOPTIONS="${XKBOPTIONS:-ctrl:nocaps}"
UEFIBOOT="${UEFIBOOT:-0}"
INSTALL_ZFS_ONLY=0

usage() {
    cat <<EOF

Configure a fresh Debian system installation.

USAGE:

$0 [OPTIONS]

Valid options are:

-a ARCH
Archicture for kernel image ${ARCH:+(default $ARCH)}

-l LOCALE
Set system locale to use (default $LOCALE)

-k KEYMAP
Keymap to be used for keyboard layout (default $KEYMAP)

-t TIMEZONE
Timezone to be used (default $TIMEZONE)

-n HOSTNAME
Hostname for the new system

-s USER
Name for sudo user instead of root

-b DEVICE
Device with boot partition to install GRUB on ${BOOTDEV:+(default $BOOTDEV)}

-z POOL
Set name for ZFS pool to be used ${ZPOOL:+(default $ZPOOL)}

-Z
Install ZFS kernel modules only, then exit

-f
Force run configuration script

-h
This usage help...

EOF
}

while getopts 'a:l:k:t:n:s:b:z:Zhf' opt
do
    case $opt in
	a)
	    ARCH=$OPTARG
	    ;;
	l)
	    LOCALE=$OPTARG
	    ;;
	k)
	    KEYMAP=$OPTARG
	    ;;
	t)
	    TIMEZONE=$OPTARG
	    ;;
	n)
	    HOSTNAME=$OPTARG
	    ;;
	s)
	    SUDOUSER=$OPTARG
	    ;;
	b)
	    BOOTDEV=$OPTARG
	    ;;
	z)
	    ZPOOL=$OPTARG
	    ;;
	Z)
	    INSTALL_ZFS_ONLY=1
	    ;;
	f)
	    FORCE_RUN=1
	    ;;
	h)
	    usage
	    exit 0
	    ;;
	:)
	    exit 1
	    ;;
	\?)
	    exit 1
	    ;;
    esac
done

shift $(($OPTIND - 1))

if [ $(id -u) -ne 0 ]
then
    ERROR_EXIT "This script must be run as root!"
fi

if [ ${LUKSV2:-0} -eq 1 -a "$(debian_version)" -lt 10 ]
then
    echo "Using LUKS format version 2 is only supported by Debian version 10 (Buster) or newer."
    exit 1
fi

if [ "$INSTALL_ZFS_ONLY" -gt 0 ]
then
    echo "Installing ZFS..."
    install_zfs
    echo "Finished installing ZFS kernel modules!"
    exit 0
fi

if [ ! -e /CONFIG_VARS.sh -a ${FORCE_RUN:-0} -lt 1 ]
then
    ERROR_EXIT "This script should be only run on a freshly bootstrapped Debian system! (Use force option to continue anyway)"
fi

if [ -z "$BOOTDEV" -a ! -z "$ROOTDEV" ]
then
    BOOTDEV=$ROOTDEV
fi

if [ -z "$BOOTDEV" ]
then
    ERROR_EXIT "boot device has to be specified!"
elif [ ! -b "$BOOTDEV" ]
then
    ERROR_EXIT "$BOOTDEV is not a block device!"
fi

if [ -z "$HOSTNAME" -o -z "$(echo $HOSTNAME | grep -E '^[[:alpha:]][[:alnum:]-]+$')" ]
then
    ERROR_EXIT "Hostname has to be specified for the new system"
fi

echo $HOSTNAME > /etc/hostname
cat >> /etc/hosts <<EOF
127.0.0.1 localhost
120.0.1.1 $HOSTNAME
::1 localhost
EOF

init_apt
init_network
apt update
apt full-upgrade -y
configure_locale $LOCALE
configure_timezone $TIMEZONE
configure_keyboard $KEYMAP $XKBOPTIONS

if [ -z "$SUDOUSER" ]
then
    cat <<EOF

You can disable root user account by creating sudo user instead.
Type username for sudo user (leave empty to keep root account enabled):
EOF
    read SUDOUSER
fi

if [ ! -z "$SUDOUSER" ]
then
    echo "Setting up SUDO user to disable root account..."
    init_sudouser "$SUDOUSER"
else
    echo "Setting password for root user..."
    passwd
fi

if [ ! -z "$ROOTDEV" ]
then
    apt install -y cryptsetup
    GRUB_MODULES="cryptodisk"
fi

if [ ! -z "$ZPOOL" ]
then
    echo "Installing ZFS..."
    install_zfs
    GRUB_MODULES="$GRUB_MODULES${GRUB_MODULES:+,}zfs"
    systemctl enable zfs-import-cache.service
    systemctl enable zfs-import-cache.target
    systemctl enable zfs-mount.service
    systemctl enable zfs-mount.target
elif [ "$SWAPFILES" -eq 0 ]
then
    echo "Installing LVM binaries..."
    apt install -y lvm2
    GRUB_MODULES="$GRUB_MODULES${GRUB_MODULES:+,}lvm"

    ### Disable udev synchronization
    if [ -e /etc/lvm/lvm.conf ]
    then
	mv /etc/lvm/lvm.conf /etc/lvm/lvm.conf.bak
	cat /etc/lvm/lvm.conf.bak |\
	    sed -re 's|(multipath_component_detection =) [0-9]+|\1 0|' |\
	    sed -re 's|(md_component_detection =) [0-9]+|\1 0|' |\
	    sed -re 's|(udev_sync =) [0-9]+|\1 0|' |\
	    sed -re 's|(udev_rules =) [0-9]+|\1 0|' > /etc/lvm/lvm.conf
    fi
fi

echo "Installing linux image and GRUB..."
if [ ! -z "$ZPOOL" ]
then
    install_kernel_zfs $ARCH
    install_grub $BOOTDEV $UEFIBOOT $ARCH $GRUB_MODULES $ZPOOL $ROOTFS
else
    apt install -y linux-image-$ARCH
    install_grub $BOOTDEV $UEFIBOOT $ARCH $GRUB_MODULES
fi

cat >> FINISH.sh <<EOF
#!/bin/sh

EOF

if [ $UEFIBOOT -eq 1 ]
then
    cat >> FINISH.sh <<EOF
umount $TARGET/boot/efi
EOF
fi

cat >> FINISH.sh <<EOF
umount $TARGET/boot
EOF

if [ ! -z "$ZPOOL" ]
then
    cat >> FINISH.sh <<EOF
zfs umount -a
zfs set mountpoint=/ $ZPOOL/$ROOTFS
zfs snapshot $ZPOOL/ROOTFS@install
zpool export $ZPOOL
echo Configured rootfs mountpoint and exported ZFS pool!
EOF
else
    cat >> FINISH.sh <<EOF
umount $TARGET
echo Unmounted $TARGET!
EOF
fi

echo
echo "FINISHED CONFIGURING NEW DEBIAN SYSTEM!"
echo

read -p "Would you like to remove configuration script and files? [y/N]" cleanup
case $cleanup in
    [yY])
	rm /CONFIG_VARS.sh /debconf.sh
	echo "Removed /debconf.sh and /CONFIG_VARS.sh"
	;;
    *)
	echo "Skipped cleaning up configuration script and files."
	;;
esac
