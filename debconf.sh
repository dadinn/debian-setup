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
    if [ "$#" -eq 1 ]
    then
	local DEV="$1"
    else
	ERROR_EXIT "called init_network with $# args: $@"
    fi

    cat > /etc/network/interfaces.d/lo <<EOF
auto lo
iface lo inet loopback
EOF
    cat > /etc/network/interfaces.d/$DEV <<EOF
auto $DEV
iface $DEV inet dhcp
EOF
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

    case $RELEASE in
	"8")
	    cat /etc/apt/sources.list | grep -E '^deb .* jessie main$' | sed -e 's/jessie main$/jessie-backports main contrib/' > /etc/apt/sources.list.d/backports.list
	    apt update
	    apt install -y -t jessie-backports zfs-dkms zfs-initramfs
	    modprobe zfs
	    ;;
	"9")
	    sed -ire 's/stretch main$/stretch main contrib/' /etc/apt/sources.list
	    apt update
	    apt install -y zfs-dkms zfs-initramfs
	    modprobe zfs
	    ;;
	*)
	    ERROR_EXIT "Debian version $RELEASE is not supported!"
	    ;;
    esac
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
}

install_grub() {
    if [ $# -eq 2 ]
    then
	local BOOTDEV="$1"
	local ARCH="$2"
    else
	ERROR_EXIT "called install_grub with $# arguments: $@"
    fi

    apt install -y cryptsetup linux-image-$ARCH
    DEBIAN_FRONTEND=noninteractive apt install -y grub-pc
    cat >> /etc/default/grub <<EOF
GRUB_CRYPTODISK_ENABLE=y
GRUB_PRELOAD_MODULES="lvm cryptodisk"
GRUB_CMDLINE_LINUX_DEFAULT=quite
GRUB_TERMINAL=console
EOF
    echo "Identifying root filesystem..."
    if grub-probe / &> /dev/null
    then
    grub-install $BOOTDEV
    update-initramfs -k all -u
    update-grub
    else
	ERROR_EXIT "grub could not identify root filesystem!"
    fi
}

# SOURCING INHERITED DEFAULTS
[ -e /CONFIG_VARS.sh ] && . /CONFIG_VARS.sh

# DEFAULTS
LOCALE="${LOCALE:-en_US.UTF-8}"
TIMEZONE="${TIMEZONE:-Europe/London}"
KEYMAP="${KEYMAP:-us:dvorak}"
XKBOPTIONS="${XKBOPTIONS:-ctrl:nocaps}"
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
init_network ens3
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

if [ ! -z "$ZPOOL" ]
then
    echo "Installing ZFS..."
    install_zfs
elif [ "$SWAPFILES" -eq 0 ]
then
    echo "Installing LVM binaries..."
    apt install -y lvm2
fi

echo "Installing linux image and GRUB..."
install_grub $BOOTDEV $ARCH

cat > FINISH.sh <<EOF
#!/bin/sh

EOF

if [ ! -z "$ZPOOL" ]
then
    cat >> FINISH.sh <<EOF
umount $TARGET/boot
zfs umount -a
zfs set mountpoint=/ $ZPOOL/$ROOTFS
zpool export $ZPOOL
echo Configured rootfs mountpoint and exported ZFS pool!
EOF
else
    cat >> FINISH.sh <<EOF
umount $TARGET/boot
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
