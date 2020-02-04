# zroot Disk Replacement

The replacment procedure missing from the handbook.  Each disk needs a freebsd-boot partition and a freebsd-zfs partition.

Here are the steps for non-efi:

```
disk="$1"
gpart destroy -F "$disk"
gpart create -s gpt "$disk"
gpart add -s 512k -t freebsd-boot "$disk"
gpart add -t freebsd-zfs "$disk"
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "$disk"
gpart show "$disk"
echo "zpool attach -f zroot ada0p2 ${disk}p2"
```
