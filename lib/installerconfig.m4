PARTITIONS=DEFAULT
DISTRIBUTIONS="kernel.txz base.txz"
export nonInteractive="YES"

#!/bin/sh
dhclient vtnet0
pkg bootstrap -y
pkg install -y openssh-portable
echo 'autoboot_delay="0"' >> /boot/loader.conf
echo PermitRootLogin=prohibit-password >> /etc/ssh/sshd_config
mkdir /root/.ssh
echo PUBKEY > /root/.ssh/authorized_keys
(
	echo "ifconfig_vtnet0=DHCP"
	echo 'hostname="freebsd-image"'
	echo 'sshd_enable="YES"'
	echo 'sendmail_enable="NONE"'
) >> /etc/rc.conf
chmod -R go-rwx /root/.ssh
(
	echo 192.168.10.8 client
	echo 192.168.10.9 mds
	echo 192.168.10.10 ds0
	echo 192.168.10.11 ds1
) >> /etc/hosts
poweroff
