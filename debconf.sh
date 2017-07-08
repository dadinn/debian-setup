#!/bin/sh

init_apt () {
    cat >> /etc/apt/apt.conf.d/norecommends <<EOF
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
EOF
}

configure_timezone () {
    dpkg-reconfigure tzdata
}

init_sudouser () {
    if [ $# -eq 1 ]
    then
	SUDOUSER=$1
    else
	echo "called init_sudouser with $# args: $@" >&2
	exit1
    fi
    useradd -m -G sudo $SUDOUSER
    passwd $SUDOUSER
    passwd -l root
}

install_zfs () {
    RELEASE=$(cat /etc/debian_version | sed -e 's;^\([0-9][0-9]*\)\..*$;\1;')
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
    [ $# -eq 1 ] && ROOTDEV="$1"
    [ ! -b $ROOTDEV ] && echo "Not a block device: $ROOTDEV" && exit 1 >&2
    apt install -y grub-pc
    grub-install $ROOTDEV
    update-grub
}

function install-zfs {
    read -p "Install ZFS tools & kernel modules? [y/N]" zfs
    case $zfs in
	[yY])
	    echo "Installing ZFS tools & kernel modules..."
	    sources-backports
	    apt install -y -t $RELEASE-backports linux-headers-$(uname -r)
	    apt install -y -t $RELEASE-backports zfs-dkms zfs-initramfs
	    echo "Finished installing ZFS tools & kernel modules!"
	    echo 'INSTALL_ZFS=1' >> $STATEFILE
	    system-reboot
	    ;;
	*)
	    echo "Skipping ZFS tools & kernel modules"
	    echo 'INSTALL_ZFS=2' >> $STATEFILE
	    ;;
    esac
}

LOCALE=${LOCALE:-en_US.UTF-8}
ZPOOL=""

usage () {
    cat <<EOF

Configure a fresh Debian system installation.

USAGE:

$0 [OPTIONS]

Valid options are:

-l LOCALE

Set system locale to use (default $LOCALE)

-s USER

Name for sudo user instead of root

-z POOL
Set name for ZFS pool to be used

EOF
}

if [ ! -e /CONFIG_ME ]
then
    echo "ERROR: this script should be only run on a freshly install Debian system" >&2
    exit 1
fi

if [ $(id -u) -ne 0 ]
then
    exit 1
fi

while getopts 'a:l:n:s:z:h' opt
do
    case $opt in
	l)
	    LOCALE=$OPTARG
	    ;;
	n)
	    HOSTNAME=$OPTARG
	    ;;
	s)
	    SUDOUSER=$OPTARG
	    ;;
	z)
	    ZPOOL=$OPTARG
	    ;;
	h)
	    usage
	    exit 0
	    ;;
	:)
	    echo "ERROR: Missing argument for potion: -$OPTARG" >&2
	    exit 1
	    ;;
	\?)
	    echo "ERROR: Illegal option -$OPTARG" >&2
	    exit 1
	    ;;
	*)
	    usage
	    exit 1
	    ;;
    esac
done

shift $(($OPTIND - 1))

if [ -z "$SUDOUSER" ]
then
    echo "ERROR: sudo user must be specified!" >&2
    exit 1
fi

init_apt
apt update
apt full-upgrade -y
apt install -y locales
locale-gen $LOCALE
configure_timezone
apt install -y console-setup
apt install -y lsb-release gdisk cryptsetup sudo

init_sudouser $SUDOUSER

if [ ! -z "$ZPOOL" ] && install_zfs
install_grub

echo "Finished configuring Debian system!"
