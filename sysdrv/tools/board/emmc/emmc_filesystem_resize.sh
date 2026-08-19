#!/bin/bash
# NOT INSTALLED BY THIS SDK'S BUILD, and NOT VALID for the frozen A/B layout.
# Nothing copies this file into a rootfs. Its p5/p6/p7 are the single-slot
# indices; under the frozen A/B table those are boot, boot_b and oem, so
# running it as written would take resize2fs to two raw FIT images. On the A/B
# layout the rootfs slot is resized by the generated /etc/init.d/S20linkmount
# instead (see the "Known asymmetry" note in
# media/joral/swupdate-implementation-plan.md). Left unmodified rather than
# corrected, because it has no role in this product.
#

# Check if the filesystem has been resized previously
if [ ! -f /etc/.filesystem_resized ]; then
	# Perform filesystem resize
	sudo resize2fs /dev/mmcblk0p5
	sudo resize2fs /dev/mmcblk0p6
	sudo resize2fs /dev/mmcblk0p7

	# Create a marker file indicating filesystem resize has been done
	sudo touch /etc/.filesystem_resized

	echo "Filesystem resized successfully."
fi

if [ ! -f /etc/.filesystem_swap ]; then
	sudo fallocate -l 1G /swapfile
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile >/dev/null
	sudo swapon /swapfile >/dev/null
	echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

	sudo touch /etc/.filesystem_swap
	echo "Swap successfully."
fi
