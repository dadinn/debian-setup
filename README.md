# debian-setup

Scripts to bootstrap Debian system on an initialized root filesystem structure. It is expected that the root filesystem structure be initialized using the [init-instroot][init-instroot] script.

It is expected that the filesystem structure contains `/etc/fstab`, `/etc/crypttab` entries, and `/CONFIG_VARS.sh` with environmental variables used to initialise the structure.

## debinst.sh

Bootstraps Debian system under target directory (default `/mnt/instroot`), and copies configuration script under it, mounts `dev`, `sys`, `run` filesystems, and starts a `chroot` shell to finish configuration by running the `debconf.sh` script.

## debconf.sh

Configure Debian on a freshly bootstrapped system under chroot. This script is copied under `/` by the `debinst.sh` script.

### Example

To configure a bootable system under chroot, setting hostname, and creating a sudo enabled user (root user will be disabled), run the following command:

	/debootstrap -n besenczy -s dadinn

This also installs all the necessary packages for LVM, LUKS, ZFS, Grub, and kernel images, and configures keyboard layouts and networks.

[init-instroot]: https://github.com/dadinn/init-instroot
