#!/bin/sh

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

bootstrap () {
    if [ $# -eq 4 ]
    then
	local TARGET=$1
	local ARCH=$2
	local RELEASE=$3
	local MIRROR=$4
    else
	ERROR_EXIT "calling bootstrap with $# args: $@"
    fi

    if ! type debootstrap 2>&1 > /dev/null
    then
	apt install -y debootstrap
    fi

    echo "Bootstrapping Debian release $RELEASE archictecture $ARCH..."
    debootstrap --arch $ARCH --include lsb-release,dirmngr,ca-certificates,xz-utils,info $RELEASE $TARGET $MIRROR
}

# DEFAULTS

RELEASE=${RELEASE:-buster}
ARCH=${ARCH:-amd64}
MIRROR=${MIRROR:-http://ftp.uk.debian.org/debian}
TARGET=${TARGET:-/mnt/instroot}

usage () {
    cat <<EOF

USAGE:

$0 [OPTIONS] COMMAND...

Bootstraps Debian in target directory, then chroots into it and executes COMMAND in the freshly bootstrapped Debian environment.

Also places configuration script debconf.sh in the target directory to help with automating the configuration.

Valid options are:

-r RELEASE
Debian release to install (default $RELEASE)

-a ARCH
The target architecture of the new system. Has to be of either amd64, arm64, armel, armhf, i368, mips, mips64el, mipsel, powerpc, ppc64el, s390x (default $ARCH)

-m URL
Debian mirror URL to install from (default $MIRROR)

-t PATH
Installation target as root directory (default $TARGET)

-X
Skip bootstrapping new system, and only execute COMMAND in chroot environment

-h
This usage help...

EOF
}

while getopts 'a:r:m:t:Xh' opt
do
    case $opt in
	a)
	    case $OPTARG in
		amd64|arm64|armel|armhf|i368|mips|mips64el|mipsel|powerpc|ppc64el|s390x)
		    ARCH=$OPTARG
		    ;;
		*)
		    ERROR_EXIT "invalid architecture $OPTARG"
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
	    TARGET=$OPTARG
	    ;;
	X)
	    EXECUTE_ONLY=1
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

CHROOT_COMMAND="$@"
if [ -z "$CHROOT_COMMAND" ]
then
    CHROOT_COMMAND="/bin/bash"
fi

if [ $(id -u) -ne 0 ]
then
    ERROR_EXIT "This script must be run as root!"
fi

if [ -z "$TARGET" -o ! -d "$TARGET" ]
then
    ERROR_EXIT "Installation target is not a directory"
fi

if [ ${EXECUTE_ONLY:-0} -ne 1 ]
then
    if ! bootstrap $TARGET $ARCH $RELEASE $MIRROR
    then
	ERROR_EXIT "Failed bootstrapping Debian under $TARGET using $MIRROR"
    fi
fi

cp $(dirname "$0")/debconf.sh $TARGET

for i in dev sys proc
do
    [ -e $TARGET/$i ] || mkdir $TARGET/$i
    mount --rbind /$i $TARGET/$i
done

echo "Executing chroot command: ${CHROOT_COMMAND}..."
LANG=C.UTF-8 ARCH=$ARCH \
chroot $TARGET $CHROOT_COMMAND

for i in dev sys proc
do umount -Rlf $TARGET/$i; done

if [ -e $TARGET/FINISH.sh ]
then
    cp $TARGET/FINISH.sh .
    rm $TARGET/FINISH.sh
    chmod 755 ./FINISH.sh
    read -p "Are you ready to execute finishing steps? [Y/n]" finish
    case $finish in
	[nN])
	    echo "Skipped executing finishing steps."
	    ;;
	*)
	    echo "Executing finishing steps..."
	    ./FINISH.sh
	    rm FINISH.sh
	    ;;
    esac
fi

echo
echo "FINISHED WITH DEBIAN INSTALLATION!"
echo

read -p "Ready to reboot the system? [y/N]" reboot
case $reboot in
    [yY])
	systemctl poweroff
	;;
    *)
	echo "Skipped rebooting for now."
	;;
esac
