XLEN     ?= 64
BOARD    ?= "genesys2"
OUTPUT   ?= $(PWD)/install$(XLEN)_$(BOARD)

FILENAME ?= 1040_307
NEW_OUTPUT ?= $(PWD)/$(FILENAME)

buildroot_defconfig_path = ../configs/$(BOARD)/buildroot$(XLEN)_defconfig
buildroot_external_tree_path := ../br2-ext-tree

all:
	mkdir -p $(OUTPUT)
	$(MAKE) -C buildroot BR2_EXTERNAL="$(buildroot_external_tree_path)" BR2_DEFCONFIG=$(buildroot_defconfig_path) defconfig
	$(MAKE) -C buildroot BINARIES_DIR=$(OUTPUT)

clean:
	rm -f $(OUTPUT)/boot.vfat $(OUTPUT)/fitImage.itb \
		$(OUTPUT)/fw_payload.bin $(OUTPUT)/fw_payload.elf \
		$(OUTPUT)/Image.gz $(OUTPUT)/rootfs.cpio $(OUTPUT)/rootfs.cpio.gz \
		$(OUTPUT)/sdcard.img \
		$(OUTPUT)/u-boot.bin $(OUTPUT)/u-boot.dtb \
		fitImage.its
	$(MAKE) -C buildroot clean

updatedefconfigs:
	$(MAKE) -C buildroot BR2_EXTERNAL="$(buildroot_external_tree_path)" BR2_DEFCONFIG=$(buildroot_defconfig_path) defconfig
	$(MAKE) -C buildroot BR2_DEFCONFIG=$(buildroot_defconfig_path) savedefconfig
	$(MAKE) -C buildroot uboot-update-defconfig
	$(MAKE) -C buildroot linux-configure
	$(MAKE) -C buildroot linux-update-defconfig


copy:
	mkdir $(NEW_OUTPUT)
	
	cp $(PWD)/buildroot/output/build/uboot-custom/spl/u-boot-spl-dtb.bin $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/spl/u-boot-spl.map $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/spl/u-boot-spl.sym $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/spl/u-boot-spl $(NEW_OUTPUT)/u-boot-spl.elf

	cp $(PWD)/buildroot/output/build/uboot-custom/u-boot.bin $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/u-boot-dtb.bin $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/u-boot.itb $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/u-boot.map $(NEW_OUTPUT)
	cp $(PWD)/buildroot/output/build/uboot-custom/u-boot.sym $(NEW_OUTPUT)

	cp $(PWD)/buildroot/output/build/opensbi-custom/build/platform/generic/firmware/fw_dynamic.bin $(NEW_OUTPUT)

	cp $(OUTPUT)/fitImage.itb $(NEW_OUTPUT)

clean_copy:
	rm -r $(NEW_OUTPUT)



.PHONY: all clean updatedefconfigs copy clean_copy
