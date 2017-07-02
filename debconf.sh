#!/bin/sh

function sources-backports {
    if [ ! -f /etc/apt/sources.list.d/backports.list ]
    then
	echo "deb http://ftp.uk.debian.org/debian $RELEASE-backports main contrib" > /etc/apt/sources.list.d/backports.list
	apt update
    fi
}

function sources-docker {
    if [ ! -f /etc/apt/sources.list.d/docker.list ]
    then
	apt install -y apt-transport-https
	echo "deb https://apt.dockerproject.org/repo debian-$RELEASE main" > /etc/apt/sources.list.d/docker.list
	wget -O - "https://apt.dockerproject.org/gpg" | apt-key add -
	apt update
    fi
}

function system-upgrade {
    echo
    read -p "Upgrade the system? [y/N]" system_upgrade
    case $system_upgrade in
	[yY])
	    echo "Upgrading Debian system..."
	    apt update
	    apt upgrade -y
	    echo "Finished upgrading Debian system!"
	    echo 'SYSTEM_UPGRADE=1' >> $STATEFILE
	    ;;
	*)
	    echo "Skipping upgrading Debian system"
	    ;;
    esac
}

function system-reboot {
    echo
    read -p "Reboot now? [Y/n]" system_reboot
    case $system_reboot in
	[nN])
	    echo "Skipping reboot. Exiting!"
	    exit 0
	    ;;
	*)
	    echo "Rebooting..."
	    reboot
	    ;;
    esac
}

function system-cleanup {
    echo
    read -p "Clean up apt repository and unneeded packages? [Y/n]" cleanup
    case $cleanup in
	[nN])
	    echo "Skipped cleaning up"
	    ;;
	*)
	    apt-get autoremove -y
	    apt-get autoclean -y
	    ;;
    esac
}

function install-grsec {
    echo
    read -p "Install grsecurity kernel patches? [y/N]" grsec
    case $grsec in
	[yY])
	    echo "Installing grsecurity kernel patches..."
	    sources-backports
	    apt install -y -t $RELEASE-backports linux-image-grsec-amd64
	    echo "Finished installing grsecurity patched kernel!"
	    echo 'INSTALL_GRSEC=1' >> $STATEFILE
	    system-reboot
	    ;;
	*)
	    echo "Skipping grsecurity kernel patches"
	    echo 'INSTALL_GRSEC=2' >> $STATEFILE
	    ;;
    esac
}

function install-samba {
    echo
    read -p "Install NFS / Samba packages? [y/N]" install_samba
    case $install_samba in
	[yY])
	    echo "Installing NFS / Samba packages..."
	    apt install -y nfs-kernel-server samba
	    echo "Finished installing NFS / Samba packages"
	    echo 'INSTALL_SAMBA=1' >> $STATEFILE
	    ;;
	*)
	    echo "Skipping NFS / Samba packages"
	    echo 'INSTALL_SAMBA=2' >> $STATEFILE
	    ;;
    esac
}


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

function install-kvm {
    echo
    read -p "Install KVM? [y/N]" kvm
    case $kvm in
	[yY])
	    echo "Installing KVM..."
	    apt install -y qemu-kvm libvirt-bin virtinst
	    echo "Finished installing KVM!"
	    echo 'INSTALL_KVM=1' >> $STATEFILE
	    echo "Check that virtualization support is enabled in BIOS!"
	    ;;
	*)
	    echo "Skipping KVM packages"
	    echo 'INSTALL_KVM=2' >> $STATEFILE
	    ;;
    esac
}

function install-docker {
    echo
    read -p "Install Docker? [y/N]" docker
    case $docker in
	[yY])
	    echo "Installing Docker..."
	    sources-docker
	    apt install -y docker-engine
	    echo "Finished installing Docker!"
	    echo 'INSTALL_DOCKER=1' >> $STATEFILE
	    ;;
	*)
	    echo "Skipping Docker Engine"
	    echo 'INSTALL_DOCKER=2' >> $STATEFILE
	    ;;
    esac
}

function install-extra {
    echo
    read -p "Install extra packages? [y/N]" extra
    case $extra in
	[yY])
	    echo "Installing extra packages..."
	    apt install -y wget tar xz-utils info
	    apt install -y gdisk cryptsetup
	    echo "Finished installing extra packages!"
	    echo 'INSTALL_EXTRA=1' >> $STATEFILE
	    ;;
	*)
	    echo "Skipping extra packages"
	    echo 'INSTALL_EXTRA=2' >> $STATEFILE
	    ;;
    esac
}

ARCH=${ARCH:-amd64}
LOCALE=${LOCALE:-en_US.UTF-8}
ZPOOL=""

usage () {
    cat <<EOF

Configure a fresh Debian system installation.

USAGE:

$0 [OPTIONS]

Valid options are:

-a ARCH
Choose architecture of the new installation (default $ARCH)

-l LOCALE

Set system locale to use (default $LOCALE)

-s USER

Name for sudo user instead of root

-z POOL
Set name for ZFS pool to be used

EOF
}

if [ $(id -u) -ne 0 ]
then
    exit 1
fi

while getopts 'a:l:n:s:z:h' opt
do
    case $opt in
	a)
	    ARCH=$OPTARG
	    ;;
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
