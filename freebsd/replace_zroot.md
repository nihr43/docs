# zroot Disk Replacement

The replacment procedure missing from the handbook.  Each disk needs a freebsd-boot partition, and a freebsd-zfs partition.

Here are the steps for non-efi:

```
gpart destroy -F ada1
gpart create -s gpt ada1
gpart add -s 512k -t freebsd-boot ada1
gpart add -t freebsd-zfs ada1
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ada1
gpart show ada1
zpool attach -f zroot ada0p3 ada1p2
```
