#!/bin/sh

RELEASE=${RELEASE:-stretch}
MIRROR=${MIRROR:-http://ftp.uk.debian.org/debian}
INSTROOT=${INSTROOT:-/mnt/instroot}

usage () {
    cat <<EOF

USAGE:

$0 [OPTIONS]

Installs Debian

Valid options are:

-r RELEASE
Debian release to install (default $RELEASE)

-m URL
Debian mirror URL to install from (default $MIRROR)

-n HOSTNAME
Hostname for new system

-k KEYMAP
Keymap to be used for keyboard layout (default dvorak)

-l LOCALE
locale to be used (default en_US.UTF8)

-t PATH
Installation target as root directory (default $INSTROOT)

-h
This usage help...
EOF
}

if [ $(id -u) -ne 0 ]
then
    echo "This script must be run as root!" >&2
    exit 1
fi

while getopts 'r:m:n:k:l:t:h' opt
do
    case $opt in
	r)
	    RELEASE=$OPTARG
	    ;;
	m)
	    MIRROR=$OPTARG
	    ;;
	n)
	    HOSTNAME=$OPTARG
	    ;;
	k)
	    KEYMAP=$OPTARG
	    ;;
	l)
	    LAYOUT=$OPTARG
	    ;;
	t)
	    INSTROOT=$OPTARG
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

if [ -z "$INSTROOT" -o ! -d "$INSTROOT" ]
then
    echo "ERROR: Installation target is not a directory" >&2
    exit 1
fi

if [ -z "$HOSTNAME" -o -z "$(echo $HOSTNAME | grep -E '^[[:alpha:]][[:alnum:]-]+$')" ]
then
    echo "ERROR: Hostname has to be specified for the new system" >&2
    exit 1
fi

apt install -y debootstrap
debootstrap $RELEASE $INSTROOT $MIRROR
echo $HOSTNAME > /etc/hostname
cp ./debconf.sh ${INSTROOT}

for i in dev sys proc
do
    [ -e $INSTROOT/$i ] || mkdir $INSTROOT/$i
    mount --bind /$i $INSTROOT/$i
done

touch $INSTROOT/CONFIG_ME
LANG=C.UTF-8 chroot $INSTROOT /debconf.sh

for i in dev sys proc
do umount $INSTROOT/$i; done
echo "Finished with Debian installation!"
