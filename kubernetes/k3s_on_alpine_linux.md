# k3s on Alpine Linux

I run `k3s` on Alpine Linux, on three small supermicro servers.  Heres how I do it.

---

First off, I use `lxd`, `terraform`, and `ansible` for stateful applications like minio, etcd, and my docker registries.  Though you can bootstrap `etcd` and `registry` inside of kubernetes itself, I like managing these core services externally to keep things simple.

Here are the relevant services running in lxd:

```
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
|          NAME           |  STATE  |       IPV4        | IPV6 |    TYPE    | SNAPSHOTS |   LOCATION   |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| docker-registry-0       | RUNNING | 10.0.0.57 (eth0)  |      | PERSISTENT | 0         | 57c9fae30ca2 |
|                         |         | 10.0.0.247 (eth0) |      |            |           |              |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| docker-registry-1       | RUNNING | 10.0.0.213 (eth0) |      | PERSISTENT | 0         | a78abd2afeef |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| etcd-0                  | RUNNING | 10.0.0.162 (eth0) |      | PERSISTENT | 0         | a78abd2afeef |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| etcd-1                  | RUNNING | 10.0.0.123 (eth0) |      | PERSISTENT | 0         | 72182231f55b |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| etcd-2                  | RUNNING | 10.0.0.212 (eth0) |      | PERSISTENT | 0         | 57c9fae30ca2 |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| haproxy-etcd-0          | RUNNING | 10.0.0.54 (eth0)  |      | PERSISTENT | 0         | a78abd2afeef |
|                         |         | 10.0.0.228 (eth0) |      |            |           |              |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| haproxy-etcd-1          | RUNNING | 10.0.0.126 (eth0) |      | PERSISTENT | 0         | 72182231f55b |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-0            | RUNNING | 10.0.0.117 (eth0) |      | PERSISTENT | 0         | a78abd2afeef |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-1            | RUNNING | 10.0.0.188 (eth0) |      | PERSISTENT | 0         | 57c9fae30ca2 |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-2            | RUNNING | 10.0.0.108 (eth0) |      | PERSISTENT | 0         | a78abd2afeef |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-3            | RUNNING | 10.0.0.105 (eth0) |      | PERSISTENT | 0         | 57c9fae30ca2 |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-4            | RUNNING | 10.0.0.127 (eth0) |      | PERSISTENT | 0         | 72182231f55b |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
| minio-prod-5            | RUNNING | 10.0.0.55 (eth0)  |      | PERSISTENT | 0         | 72182231f55b |
|                         |         | 10.0.0.211 (eth0) |      |            |           |              |
+-------------------------+---------+-------------------+------+------------+-----------+--------------+
```

- `docker-registry`: two instances backed by minio for storage, using keepalived for floating ip.  Effectively stateless.
- `etcd`: core data store for k3s.
- `haproxy-etcd`: tcp mode haproxy instances for etcd.  Using keepalived for floating ip.  Backends dynamically configured through ansible:

```
backend nodes
    mode {{ mode }}
    balance {{ balance }}
    {% for host in groups[proxied_group] %}
    server {{ host }} {{ host }}:{{ back_bind_port }} check init-addr none resolvers dns inter 1000
    {% endfor %}
```

- `minio-prod`: core data store for many services.  Using `MINIO_STORAGE_CLASS_STANDARD=EC:3` and overprovisioning 6 instances on 3 physical nodes, I'm safe to reboot/rebuild any one server or any two containers.  minio doesn't support odd numbered cluster sizes for some reason.  These are not load balanced; just a single vip via keepalived for maximum transfer throughput.  Tuning haproxy for object storage can be tricky.

The physical nodes only run lxd, k3s, and some standard daemons like sshd, filebeat, haveged.  All other services are contained.

tcp load balancers for the lxd management api are themselves running in lxd.

The servers themselves are 1u half-rack supermicro servers each with non-ecc ram and mdadm raid0 over used ebay ssds.  The approach here is to use the cheapest viable hardware and address reliability in software.

With this setup, I can freely upgrade and reboot physical servers without affecting service.  (for the most part.  active tcp connections to minio, for instance, will be dropped when the vip flips.)

---

With the prerequisites out of the way, lets talk `k3s`.

Heres my current ansible `roles/k3s_master/tasks/main.yml`:

```
---

- name: install role packages
  package: name=k3s state=present

- name: configure k3s conf.d
  template:
   src: k3s.conf.d
   dest: /etc/conf.d/k3s
   owner: root
   group: root
   mode: '0600'
  notify: restart k3s

- name: configure k3s registries
  template:
   src: registries.yml
   dest: /etc/rancher/k3s/registries.yaml
   owner: root
   group: root
   mode: '0644'
  notify: restart k3s

- name: copy cni plugins to viable PATH
  copy:
   src: /usr/share/cni-plugins/bin/
   dest: /usr/local/bin/
   mode: preserve
   remote_src: true

- name: enforce /usr/local/bin permissions
  file:
   path: /usr/local/bin
   state: directory
   mode: '0755'
   recurse: true

- name: start and enable k3s
  service:
   name: k3s
   enabled: true
   state: started
```

`k3s` is in the `edge/testing` repo by the way.  I manage repos in a different role.

Heres `conf.d/k3s`.  Yes, I need to get around to setting up tls for my etcd cluster.

```
K3S_OPTS="--datastore-endpoint http://{{ k3s_etcd }}:2379 --token {{ lookup ('env', 'K3S_TOKEN') }} --node-name {{ ansible_hostname }} --log /var/log/k3s.log"
```

As I only have three k3s nodes, all nodes are masters.

`/etc/rancher/k3s/registries.yaml`:

```
mirrors:
  "10.0.0.57:5000":
    endpoint:
      - "http://10.0.0.57:5000"
```

As far as I can remember, thats everything I've done to get k3s to run on alpine.  Even using k8s bundled as k3s, there are still a lot of pieces to manage in a fully HA setup like this.  I've put a lot of time into developing, testing, and perfecting supporting roles like `haproxy`, `keepalived`, `alpine_common`, `physical_common`, and of course a rolling upgrade play, so I can manage all this as "a handful of services" rather than 30-40 containers.

```
72182231f55b [~]# kubectl get nodes
NAME           STATUS   ROLES    AGE    VERSION
57c9fae30ca2   Ready    master   4d1h   v1.16.3-k3s.2
72182231f55b   Ready    master   4d     v1.16.3-k3s.2
a78abd2afeef   Ready    master   4d     v1.16.3-k3s.2
72182231f55b [~]# kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
default       grafana-75c8b47767-qxhrq                  1/1     Running   2          4d
default       kibana-5c989b947f-2f6mk                   1/1     Running   3          3d23h
default       kibana-5c989b947f-89zbw                   1/1     Running   2          3d23h
default       mkdocs-56b8d99c8d-h4nx6                   1/1     Running   2          93m
default       mkdocs-56b8d99c8d-qlblq                   1/1     Running   4          93m
kube-system   coredns-d798c9dd-rbpw4                    1/1     Running   2          4d
kube-system   local-path-provisioner-58fb86bdfd-tkrfl   1/1     Running   5          4d
kube-system   metrics-server-6d684c7b5-fjfws            1/1     Running   2          4d
kube-system   svclb-traefik-8b58d                       3/3     Running   9          4d
kube-system   svclb-traefik-nkbst                       3/3     Running   6          4d
kube-system   svclb-traefik-slsm6                       3/3     Running   6          4d
kube-system   traefik-65bccdc4bd-qqpx5                  1/1     Running   2          4d
```
