# Expanding zpools

To expand a pool when drives are upgraded:

```
zpool set autoexpand=on zroot
```

The above needs to be set before the drives are replaced.  If forgotten, manually trigger expansion for each device:

```
zpool online -e zroot ada0p2
zpool online -e zroot ada1p2
```
