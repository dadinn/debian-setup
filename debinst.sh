#!/bin/sh

RELEASE=jessie
MIRROR=http://ftp.uk.debian.org/debian
INSTROOT=/mnt/inst_root

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

-t PATH
Installation target as root directory (default $INSTROOT)

-h
This usage help...
EOF
}

while getopts 'r:m:n:t:h' opt
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

if [ -z "$HOSTNAME" -o -z "$(echo $HOSTNAME | grep -E '^[[:alpha:]][[:alnum:]-]+$')" ]
then
    echo "ERROR: Hostname has to be specified for the new system" >&2
    exit 1
fi

apt install -y debootstrap
debootstrap $RELEASE $INSTROOT $MIRROR
