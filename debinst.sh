#!/bin/sh

RELEASE=${RELEASE:-stretch}
ARCH=${ARCH:-amd64}
MIRROR=${MIRROR:-http://ftp.uk.debian.org/debian}
INSTROOT=${INSTROOT:-/mnt/instroot}

bootstrap () {
    if [ $# -eq 3 ]
    then
	local INSTROOT=$1
	local ARCH=$2
	local RELEASE=$3
	local MIRROR=$4
    else
	echo "ERROR: calling bootstrap with $# args: $@" >&2
	exit 1
    fi

    if ! type debootstrap 2>&1 > /dev/null
    then
	apt install -y debootstrap
    fi

    echo "Bootstrapping Debian release $RELEASE archictecture $ARCH..."
    debootstrap --arch $ARCH --include lsb-release $RELEASE $INSTROOT $MIRROR
}

usage () {
    cat <<EOF

USAGE:

$0 [OPTIONS]

Installs Debian

Valid options are:

-r RELEASE
Debian release to install (default $RELEASE)

-a ARCH
The target architecture of the new system. Has to be of either amd64, arm64, armel, armhf, i368, mips, mips64el, mipsel, powerpc, ppc64el, s390x (default $ARCH)

-m URL
Debian mirror URL to install from (default $MIRROR)

-t PATH
Installation target as root directory (default $INSTROOT)

-C
Skip bootstrapping new system, and only setup chroot environment into target root directory

-h
This usage help...

EOF
}

while getopts 'a:r:m:t:Ch' opt
do
    case $opt in
	a)
	    case $OPTARG in
		amd64|arm64|armel|armhf|i368|mips|mips64el|mipsel|powerpc|ppc64el|s390x)
		    ARCH=$OPTARG
		    ;;
		*)
		    echo "ERROR: invalid architecture $OPTARG" >&2
		    exit 1
		    ;;
	    esac
	    ;;
	r)
	    RELEASE=$OPTARG
	    ;;
	m)
	    MIRROR=$OPTARG
	    ;;
	t)
	    INSTROOT=$OPTARG
	    ;;
	C)
	    CONFIG_ONLY=1
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
    echo "This script must be run as root!" >&2
    exit 1
fi

if [ -z "$INSTROOT" -o ! -d "$INSTROOT" ]
then
    echo "ERROR: Installation target is not a directory" >&2
    exit 1
fi

if [ ${CONFIG_ONLY:-0} -lt 1 ]
then
    bootstrap $INSTROOT $ARCH $RELEASE $MIRROR
fi

cp ./debconf.sh ${INSTROOT}

for i in dev sys proc
do
    [ -e $INSTROOT/$i ] || mkdir $INSTROOT/$i
    mount --bind /$i $INSTROOT/$i
done

touch $INSTROOT/CONFIG_ME
if [ ${CONFIG_ONLY:-0} -lt 1 ]
then
    LANG=C.UTF-8 chroot $INSTROOT /debconf.sh
else
    LANG=C.UTF-8 chroot $INSTROOT /bin/bash
fi

for i in dev sys proc
do umount $INSTROOT/$i; done
echo "Finished with Debian installation!"
