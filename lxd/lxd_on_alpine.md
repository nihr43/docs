# Stateful System Containers with lxd

~lxd provides a substrate on which to deploy and run containers using traditional devops tools.~

---

I run lxd on bare metal rather than VMs for stateful services and traditional network functions.  System containers provide the high efficiency of OS virtualization while maintaining compatability with traditional configuration management tools.  For my needs, this approach is more appropriate than kubernetes for various pre-'cloud-native computing' services such as dhcpd, jenkins, or traditional relational databases.  I also run k8s support infrastructure using lxd, namely etcd and docker-registry.  This post is not a guide on how to install and setup lxd, but rather a collection of notes on integration and automation of lxd overall.

---

~implementation~

Lets look at how to deploy a highly available docker registry on top of lxd.  We will use ansible, terraform, and the [lxd terraform provider](https://github.com/sl1pm4t/terraform-provider-lxd).

First of all we need to define a provider:

```
provider "lxd" {
  generate_client_certificates = true
  accept_remote_certificate    = true

  lxd_remote {
    name     = "10.0.0.100"
    scheme   = "https"
    address  = "10.0.0.100"
    password = "ce9dbb78703fb47147a65796b30c74b8"
    default  = true
  }
}
```

`10.0.0.100` is the address of a tcp load balancer, ensuring terraform will still function if a node is missing.

After installing the plugin and running `terraform init`, we can start acting on the cluster.

In order to build and provision containers in a single operation, I use the following shell script as a provisioner:

```
#!/bin/sh

instance="$1"
current_node="$(lxc info "$instance" \
                  | awk '/Location: /{print $NF}')"
target_node="$(lxc cluster ls --format json \
                 | jq -r .[].server_name \
                 | shuf -n2 \
                 | shuf -n1)"

# lxd crashes if you attempt a no-op move
[ "$target_node" = "$current_node" ] || {
  printf "\033[0;32mrebalancing %s from %s to %s\033[0m" "$instance" \
                                                         "$current_node" \
                                                         "$target_node"
  lxc stop "$instance"
  lxc mv "$instance" --target="$target_node"
  lxc start "$instance"
}

lxc exec "$instance" -- sh -c '
  cat > /etc/apk/repositories << EOF
http://10.0.0.55:9000/alpine/v3.11/main
http://10.0.0.55:9000/alpine/v3.11/community
http://10.0.0.55:9000/alpine/edge/testing
EOF
  apk update
  apk upgrade --no-cache
  apk add openssh python3 --no-cache
  passwd -u root
  sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g" /etc/ssh/sshd_config
  mkdir /root/.ssh
  wget https://github.com/nihr43.keys -O /root/.ssh/authorized_keys
  rc-update add sshd
  rc-service sshd start
'

ansible-playbook ./main.yml --limit="$instance"
```

The first half of this is a work around the fact that the lxd module does not evenly balance new containers across the cluster.  Then we use `lxc exec` to run minimal setup required to run ansible against the node, and then finally we run ansible to apply a role.  This requires the node already exists in the ansible inventory.

Now for the docker-registry specification:

```
resource "lxd_container" "docker-registry" {
  count     = 2
  name      = "docker-registry-${count.index}"
  image     = "alpine/stable"
  provisioner "local-exec" { command = "scripts/provision_alpine.sh ${self.name}" }
}
```

`terraform apply` will now build two new docker registry nodes.  These registries share an IP using keepalived and use s3 backed storage, making them entirely disposable - though I won't show the whole role in this post.

A key component to note is the use of the `alpine/stable` image.  In fact, there is no such alpine release; this is an alias used to synchronize the base image of all new containers, and to avoid forced rebuilds when it comes time to upgrade.  This alias itself is managed using terraform:

```
resource "lxd_cached_image" "alpine" {
  source_remote = "images"
  source_image  = "alpine/3.11"
  aliases = ["alpine/stable"]
}
```
