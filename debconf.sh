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
    [ $# -eq 1 ] && ROOTDEV="$1"
    [ ! -b $ROOTDEV ] && echo "Not a block device: $ROOTDEV" && exit 1 >&2
    apt install -y grub-pc
    grub-install $ROOTDEV
    update-grub
}

LOCALE=${LOCALE:-en_US.UTF-8}
KEYMAP=${KEYMAP:-dvorak}
TIMEZONE="Europe/London"

usage () {
    cat <<EOF

Configure a fresh Debian system installation.

USAGE:

$0 [OPTIONS]

Valid options are:

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

-z POOL
Set name for ZFS pool to be used

-f
Force run configuration script

-h
This usage help...

EOF
}

while getopts 'l:k:t:n:s:z:h' opt
do
    case $opt in
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

if [ -z "$SUDOUSER" ]
then
    echo "ERROR: sudo user must be specified!" >&2
    exit 1
fi

if [ -z "$HOSTNAME" -o -z "$(echo $HOSTNAME | grep -E '^[[:alpha:]][[:alnum:]-]+$')" ]
then
    echo "ERROR: Hostname has to be specified for the new system" >&2
    exit 1
fi

echo $HOSTNAME > /etc/hostname

init_apt
apt update
apt full-upgrade -y
configure_locale $LOCALE
configure_timezone $TIMEZONE
apt install -y console-setup
apt install -y lsb-release gdisk cryptsetup sudo

init_sudouser $SUDOUSER

if [ ! -z "$ZPOOL" ]
then
    install_zfs
fi

install_grub

echo "Finished configuring Debian system!"
