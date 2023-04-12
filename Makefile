Git != git describe --always --dirty
Wait = function wt { i=$$1; shift; touch $@.w; while :; do echo -e "Waiting for '$@.$$i'. $$(( $$(date +%s) - $$(stat -c %Y $@.w) )) seconds."; ! $(SHELL) -c "$$*" || break;  sleep 2; done; rm -f $@.w; }; wt
Ssh = ssh -oIdentityAgent=none -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=error -oConnectTimeout=2 -i var/id_ed25519
define DaikerRun
	-fuser -k $@.qcow2 $1/tcp
	rm -f $@.qcow2
	lfs/daiker run -e random -T 22-$1 -b $<.qcow2 $@.qcow2 &
	$(Wait) 0 $(Ssh) -p $1 root@localhost hostname
endef
define DaikerReboot
	-$(Ssh) -p $1 root@localhost reboot
	$(Wait) 0 $(Ssh) -p $1 root@localhost hostname
	touch $@
endef
var/client : var/build var/mds
	$(call DaikerRun,2218)
	$(Ssh) -p 2218 root@localhost <<< '\
		sed -i.bak -e s/freebsd-image/client/ /etc/rc.conf && \
		( echo ifconfig_vtnet1=\"inet 192.168.10.8 netmask 255.255.255.0\" && \
			echo nfsuserd_enable=\"YES\" && \
			echo nfscbd_enable=\"YES\" \
		) >> /etc/rc.conf && \
		echo mds:/ /mnt nfs rw,nfsv4,minorversion=2,soft,retrans=2,pnfs 0 0 >> /etc/fstab'
	$(call DaikerReboot,2218)
var/mds : var/build var/ds0 var/ds1
	$(call DaikerRun,2219)
	$(Ssh) -p 2219 root@localhost <<< '\
		sed -i.bak -e s/freebsd-image/mds/ /etc/rc.conf && \
		( echo ifconfig_vtnet1=\"inet 192.168.10.9 netmask 255.255.255.0\" && \
			echo mountd_enable=\"YES\" && \
			echo nfsuserd_enable=\"YES\" && \
			echo nfs_server_enable=\"YES\" && \
			echo nfsv4_server_enable=\"YES\" && \
			echo nfsv4_server_only=\"YES\" && \
			echo nfs_server_flags=\"-t -n 4 -p ds0:/data0,ds1:/data1\" && \
			echo rpcbind_enable=\"YES\" \
		) >> /etc/rc.conf && \
		( echo V4: /export && echo /export -maproot=root -sec=sys ) > /etc/exports && \
		mkdir -m 700 /export /data0 /data1 && \
		( \
			echo ds0:/ /data0 nfs rw,nfsv4,minorversion=2,soft,retrans=2 0 0 && \
			echo ds1:/ /data1 nfs rw,nfsv4,minorversion=2,soft,retrans=2 0 0 \
		) >> /etc/fstab'
	$(call DaikerReboot,2219)
var/ds% : var/build
	$(call DaikerRun,222$*)
	$(Ssh) -p 222$* root@localhost <<< '\
		sed -i.bak -e s/freebsd-image/ds$*/ /etc/rc.conf && \
		( echo ifconfig_vtnet1=\"inet 192.168.10.1$* netmask 255.255.255.0\" && \
			echo mountd_enable=\"YES\" && \
			echo nfsuserd_enable=\"YES\" && \
			echo nfs_server_enable=\"YES\" && \
			echo nfsv4_server_enable=\"YES\" && \
			echo nfsv4_server_only=\"YES\" && \
			echo nfs_server_flags=\"-t -n 4\" && \
			echo rpcbind_enable=\"YES\" \
		) >> /etc/rc.conf && \
		( echo V4: /DSstore && echo /DSstore -maproot=root -sec=sys ) > /etc/exports && \
		mkdir -m 700 /DSstore && \
		cd /DSstore && \
		jot -w ds 20 0 | xargs mkdir -m 700'
	$(call DaikerReboot,222$*)
var/build : var/pnfs.iso lfs/daiker
	-fuser -k $@.qcow2
	rm -f $@.qcow2
	lfs/daiker build -H 10 -i $< $@.qcow2
	touch $@
var/pnfs.iso : lfs/FreeBSD-13.2-RELEASE-amd64-disc1.iso var/installerconfig
	#Credit to https://unix.stackexchange.com/questions/487895/how-to-create-a-freebsd-iso-with-mkisofs-that-will-boot-in-virtualbox-under-uefi 
	rm -rf $@.d
	mkdir -p $@.d
	bsdtar -xC $@.d -f $<
	cp var/installerconfig $@.d/etc
	echo 'autoboot_delay="0"' >> $@.d/boot/loader.conf
	dd if=$< bs=1 count=446 of=$@.mbr_code.img
	xorriso -indev $< -report_el_torito plain -report_system_area plain > $<.info
	dd if=$< bs=2048 skip=$$(grep '^El Torito boot img :   1  BIOS' $<.info | tr -s " " | cut -d " " -f 13) count=$$(grep '^El Torito img blks :   1' $<.info | tr -s " " | cut -d " " -f 7) of=$@.bios_boot.img
	dd if=$< bs=2048 skip=$$(grep '^El Torito boot img :   2  UEFI' $<.info | tr -s " " | cut -d " " -f 13) count=$$(grep '^El Torito img blks :   2' $<.info | tr -s " " | cut -d " " -f 7) of=$@.efi_part.img
	xorriso \
		-system_id $(Git) \
		-as mkisofs \
		-o $@.tmp -d -l -r \
		-V "$$(isoinfo -i $< -d | grep '^Volume id:' |cut -c 12-)" \
		-G $@.mbr_code.img \
		-b /${@F}.bios_boot.img -no-emul-boot -boot-load-size 4 \
		-eltorito-alt-boot \
		-append_partition 2 0xef $@.efi_part.img \
		-e '--interval:appended_partition_2:all::' \
       	-no-emul-boot \
        $@.bios_boot.img $@.d
	mv $@.tmp $@
lfs/daiker :
	mkdir -p $(@D)
	wget -cO $@.tmp https://raw.githubusercontent.com/daimh/daiker/master/daiker
	chmod +x $@.tmp
	mv $@.tmp $@
lfs/FreeBSD-13.2-RELEASE-amd64-disc1.iso :
	mkdir -p $(@D)
	wget -cO $@.xz https://download.freebsd.org/ftp/releases/ISO-IMAGES/13.2/FreeBSD-13.2-RELEASE-amd64-disc1.iso.xz
	unxz $@.xz
	touch $@
var/installerconfig : lib/installerconfig.m4 var/id_ed25519
	m4 -D PUBKEY="$$(cat var/id_ed25519.pub)" $< > $@
var/id_ed25519 :
	mkdir -p $(@D)
	ssh-keygen -N "" -t ed25519 -f $@
