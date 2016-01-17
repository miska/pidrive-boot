CROSS_COMPILE=$(CCACHE) arm-linux-gnueabihf-
LINUX_CONFIG_METHOD=olddefconfig
BBV=1.23.2
JOBS=-j`cat /proc/cpuinfo | grep ^processor | wc -l`
KV=4.1.15+

all: SD/all

# Final layout for SD card

SD/all: SD/kernel7.img SD/bcm2709-rpi-2-b.dtb SD/config.txt SD/start.elf SD/modules.squash SD/rootfs.squash

download/owncloud/index.php:
	cd download;\
	git clone https://github.com/owncloud/core.git owncloud;\
	cd owncloud;\
	git checkout -b stable8.2 origin/stable8.2;\
	git submodule init;\
	git submodule update;\
	cd apps;\
	git clone https://github.com/miska/ocipv6.git

download/opensuse.tbz:
	wget -O $@ http://download.opensuse.org/ports/armv7hl/distribution/13.2/appliances/openSUSE-13.2-ARM-JeOS.armv7-rootfs.armv7l-Current.tbz

SD/rootfs.squash: src/init-rootfs download/opensuse.tbz download/owncloud/index.php
	mkdir -p build/opensuse
	cat src/init-rootfs | sudo bash

SD/start.elf: build/blobs/boot/start.elf
	mkdir -p SD
	cp build/blobs/boot/bootcode.bin SD
	cp build/blobs/boot/start*.elf SD
	cp build/blobs/boot/fixup*.dat SD
	cp build/blobs/boot/[LC]* SD

SD/modules.squash: build/modules/lib/modules/$(KV)/modules.dep
	rm -f $@
	mksquashfs build/modules/lib/modules/$(KV) SD/modules.squash -comp xz -all-root

SD/kernel7.img: build/kernel7.img
	mkdir -p SD; cp $< $@

SD/bcm2709-rpi-2-b.dtb: build/linux/arch/arm/boot/dts/bcm2709-rpi-2-b.dtb
	mkdir -p SD; cp $< $@
	mkdir -p SD/overlays; cp build/linux/arch/arm/boot/dts/overlays/*.dtb SD/overlays

SD/config.txt: src/config.txt
	mkdir -p SD; cp $< $@

SD/cmdline.txt: src/cmdline.txt
	mkdir -p SD; cp $< $@

# Get Busybox
download/busybox-$(BBV).tar.bz2:
	mkdir -p download
	cd download && wget -c http://busybox.net/downloads/busybox-$(BBV).tar.bz2

build/busybox/Makefile: download/busybox-$(BBV).tar.bz2
	rm -rf "`dirname "$@"`"; mkdir -p "`dirname "$@"`" && tar -xjf download/busybox-$(BBV).tar.bz2 --strip-components=1 -C "`dirname "$@"`"; \
	[ -s "$@" -o -d "$@" ] && touch $@

build/busybox/.config: build/busybox/Makefile src/busybox-config
	cp -pf src/busybox-config $@
	cd build/busybox && $(MAKE) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" oldconfig
	[ -s "$@" -o -d "$@" ] && touch $@

build/busybox/busybox: build/busybox/.config 
	cd build/busybox && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)"

build/init/bin/busybox: build/busybox/busybox
	cd build/busybox && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" CONFIG_PREFIX=`pwd`/../init install

# Create initrd filelist

build/init-list: build/bb-list src/dev-list
	echo file /init `pwd`/src/init 755 0 0 > $@
	echo dir /sbin 755 0 0 >> $@
	echo dir /bin 755 0 0 >> $@
	echo dir /usr 755 0 0 >> $@
	echo dir /usr/sbin 755 0 0 >> $@
	echo dir /usr/bin 755 0 0 >> $@
	echo slink /sbin/init ../init 777 0 0 >> $@
	echo dir /dev 755 0 0 >> $@
	echo dir /dev/pts 755 0 0 >> $@
	echo dir /mnt 755 0 0 >> $@
	echo dir /proc 755 0 0 >> $@
	echo dir /sys 755 0 0 >> $@
	echo dir /tmp 755 0 0 >> $@
	cat $^ >> $@

build/bb-list: build/init/bin/busybox
	echo file /bin/busybox `pwd`/$< 755 0 0 > $@
	cd build/init && find . -type l | while read file; do \
	  echo slink `echo $$file | sed 's|^\.||'` `readlink $$file` 777 0 0; \
	done >> ../bb-list

# Get kernel
build/linux/Makefile:
	rm -rf "`dirname "$@"`"; mkdir -p build && \
	cd build && \
	git clone --depth=1 https://github.com/raspberrypi/linux

build/blobs/boot/start.elf:
	rm -rf "`dirname "$@"`"; mkdir -p build && \
	cd build && \
	git clone --depth=1 https://github.com/raspberrypi/firmware blobs

build/linux/.config: src/linux-config build/linux/Makefile
	cp -pf $< $@
	cd "`dirname "$@"`" && $(MAKE) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" olddefconfig
	sed -i 's|^.*CONFIG_INITRAMFS_SOURCE.*|CONFIG_INITRAMFS_SOURCE="'`pwd`'/build/init-list"|' $@
	[ -s "$@" -o -d "$@" ] && touch $@

# Build stuff

build/linux/arch/arm/boot/zImage: build/linux/Makefile build/linux/.config build/init-list src/init
	export KERNEL=kernel7 && cd build/linux && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" zImage
	[ -s "$@" -o -d "$@" ] && touch $@

build/linux/arch/arm/boot/dts/bcm2709-rpi-2-b.dtb: build/linux/Makefile build/linux/.config
	export KERNEL=kernel7 && cd build/linux && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" dtbs

build/kernel7.img: build/linux/arch/arm/boot/zImage
	build/linux//scripts/mkknlimg $< $@

build/linux/modules.order: build/linux/arch/arm/boot/zImage
	cd build/linux && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" modules
	[ -s "$@" -o -d "$@" ] && touch $@

build/modules/lib/modules/$(KV)/modules.dep: build/linux/modules.order
	rm -rf build/modules; mkdir -p build/modules
	cd build/linux && $(MAKE) $(JOBS) ARCH=arm CROSS_COMPILE="$(CROSS_COMPILE)" INSTALL_MOD_PATH=`pwd`/../modules modules_install
	[ -s "$@" -o -d "$@" ] && touch $@

