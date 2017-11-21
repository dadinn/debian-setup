#!/bin/sh

init_apt () {
    cat >> /etc/apt/apt.conf.d/norecommends <<EOF
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
EOF
}

configure_locale () {
    if [ $# -eq 1 ]
    then
	local LOCALE=$1
    else
	echo "called init_locales with $# args: $@" >&2
	exit 1
    fi

    apt install -y locales
    locale-gen $LOCALE
}

configure_timezone () {
    if [ $# -eq 1 ]
    then
	local TIMEZONE=$1
    else
	echo "ERROR: called configure_timezone with $# args: $@" >&2
	exit 1
    fi

    ZONEFILE="/usr/share/zoneinfo/$TIMEZONE"

    if [ ! -e $ZONEFILE ]
    then
	echo "ERROR: /usr/share/zoneinfo/$TIMEZONE does not exist!" >&2
	exit 1
    fi

    apt install -y tzdata
    ln -sf $ZONEFILE /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata
}

init_sudouser () {
    if [ $# -eq 1 ]
    then
	SUDOUSER=$1
    else
	echo "called init_sudouser with $# args: $@" >&2
	exit 1
    fi

    apt install -y sudo
    useradd -m -G sudo $SUDOUSER
    passwd $SUDOUSER
    passwd -l root
}

install_zfs () {
    if [ $# -eq 0 ]
    then
	RELEASE=$(cat /etc/debian_version | sed -e 's;^\([0-9][0-9]*\)\..*$;\1;')
    else
	echo "ERROR: called install_zfs with $# args: $@" >&2
	exit 1
    fi

    case $RELEASE in
	"8")
	    echo /etc/apt/sources.list | grep -E '^deb .* jessie main$' | sed -e 's/jessie main/jessie-backports main contrib/' > /etc/apt/sourced.list.d/backports.list
	    apt update
	    apt install -y -t jessie-backports zfs-dkms zfs-initramfs
	    modprobe zfs
	    ;;
	"9")
	    sed -ire 's/^deb (.+) stretch main$/deb \1 stretch main contrib/' /etc/apt/sources.list
	    apt update
	    apt install -y zfs-dkms zfs-initramfs
	    modprobe zfs
	    ;;
	*)
	    echo "ERROR: Debian version $RELEASE is not supported!"
	    exit 1
	    ;;
    esac
}

install_grub () {
    if [ $# -eq 2 ]
    then
	local BOOT_DEV=$1
	local ARCH=$2
    else
	echo "called install_grub with $# arguments: $@" >&2
	exit 1
    fi

    apt install -y cryptsetup linux-image-$ARCH
    DEBIAN_FRONTENT=noninteractive apt install -y grub-pc
    cat >> /etc/default/grub <<EOF
GRUB_CRYPTODISK_ENABLE=y
GRUB_PRELOAD_MODULES="lvm cryptodisk"
EOF
    grub-install $BOOT_DEV
    update-initramfs -k all -u
    update-grub
}

# SOURCING INHERITED DEFAULTS
[ -e /CONFIG_ME ] && . /CONFIG_ME
BOOT_DEV=$ROOT_DRIVE

# DEFAULTS
LOCALE=${LOCALE:-en_US.UTF-8}
KEYMAP=${KEYMAP:-dvorak}
TIMEZONE="Europe/London"

usage () {
    cat <<EOF

Configure a fresh Debian system installation.

USAGE:

$0 [OPTIONS]

Valid options are:

-a ARCH
Archicture to user for kernel image

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
Device with boot partition to install GRUB on (default $BOOT_DEV)

-z POOL
Set name for ZFS pool to be used

-f
Force run configuration script

-h
This usage help...

EOF
}

while getopts 'a:l:k:t:n:s:b:z:h' opt
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
	    BOOT_DEV=$OPTARG
	    ;;
	z)
	    ZPOOL=$OPTARG
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
    echo "ERROR: This script must be run as root!" >&2
    exit 1
fi

if [ ! -e /CONFIG_ME -a ${FORCE_RUN:-0} -lt 1 ]
then
    echo "ERROR: This script should be only run on a freshly bootstrapped Debian system! (Use force option to continue anyway)" >&2
    exit 1
fi

if [ -z "$BOOT_DEV" ]
then
    echo "ERROR: boot device has to be specified for GRUB!" >&2
    exit 1
elif [ ! -b "$BOOT_DEV" ]
then
    echo "ERROR: $BOOT_DEV is not a block device!" >&2
    exit 1
fi

if [ -z "$HOSTNAME" -o -z "$(echo $HOSTNAME | grep -E '^[[:alpha:]][[:alnum:]-]+$')" ]
then
    echo "ERROR: Hostname has to be specified for the new system" >&2
    exit 1
fi

echo $HOSTNAME > /etc/hostname
cat >> /etc/hosts <<EOF
172.0.0.1 $HOSTNAME
::1 $HOSTNAME
EOF

init_apt
apt update
apt full-upgrade -y
configure_locale $LOCALE
configure_timezone $TIMEZONE
apt install -y console-setup

if [ ! -z "$ZPOOL" ]
then
    echo "Installing ZFS..."
    install_zfs
elif [ "$SWAPFILES" -eq 0 ]
then
    echo "Installing LVM binaries..."
    apt install -y lvm2
fi

if [ ! -z "$SUDOUSER" ]
then
    init_sudouser $SUDOUSER
else
    echo "Setting password for root user..."
    passwd
fi

install_grub $BOOT_DEV $ARCH

echo "Finished configuring Debian system!"
