# Stateful System Containers with lxd

_jan 2020_

lxd provides a substrate on which to deploy and run containers using traditional devops tools

---

This post is not a guide on how to install and setup lxd, but rather a collection of notes on integration and automation of lxd overall.

I run lxd containers rather than VMs for stateful services and traditional network functions.  System containers provide the O(1) efficiency of OS virtualization while maintaining compatability with traditional configuration management tools (they look and act like VMs).  For my needs, this approach is more appropriate than kubernetes for various non-cloud-native services such as dhcpd, traditional relational databases, or a monolithic app like jenkins.  Concerning network functions, system containers are a good choice for running HAproxy groups or name servers with virtual IPs.  They are also a good choice for running storage services, database, or kubernetes support services such as `etcd`.

Are containers as safe as hardware virtualization?  Probably not.  Though post-spectre, the lines here are blurred.  No, I wouldn't host a public cloud on linux containers, but personally, these concerns are dwarfed by my fears of misconfiguration or negligence.  In this environment, the efficiency / security tradeoff is acceptable.

---

_implementation_

Lets look at how to deploy a highly available docker registry on top of lxd.  We will use ansible, terraform, and the [lxd terraform provider](https://github.com/sl1pm4t/terraform-provider-lxd).

First of all we need to define a provider:

```
provider "lxd" {
  generate_client_certificates = true
  accept_remote_certificate    = true

  lxd_remote {
    name     = "lxd.localnet"
    scheme   = "https"
    address  = "lxd.localnet"
    password = var.LXD_PASS
    default  = true
  }
}
```

`lxd.localnet` is a round-robin DNS record across the lxd nodes, ensuring terraform will still function if a node is missing.  `var.LXD_PASS` is the admin password for the cluster, pulled from the shell environment.

After installing the plugin and running `terraform init`, we can start acting on the cluster.

In order to build and provision containers in a single operation, I use the following shell script as a provisioner:

```
#!/bin/sh
#
# provision a base alpine container

hash lxc jq ansible-playbook || {
  echo "missing dependencies"
  exit 1
}

instance="$1"

# execute minimal setup over api
lxc exec "$instance" -- sh -c '
  until ping -c1 10.0.0.1 ; do
    sleep 1
  done
  set -e
  apk update
  apk add openssh python3 --no-cache
  passwd -u root
  sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g" /etc/ssh/sshd_config
  mkdir /root/.ssh
  wget https://github.com/nihr43.keys -O /root/.ssh/authorized_keys
  rc-update add sshd
  rc-service sshd start
' || {
  exit 1
}

# upgrade and provision
ansible-playbook ./actions/alpine_update/tasks/main.yml --limit="$instance"
ansible-playbook ./main.yml --limit="$instance"
```

The first half of this is a work around the fact that the lxd module does not evenly balance new containers across the cluster.  Then we use `lxc exec` to run minimal setup required to run ansible against the node, and then finally we run ansible to apply a role.  This requires the node already exists in the ansible inventory.

Now for the docker-registry terrform spec:

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

---

_challenges_

lxd's dqlite raft implementation is quite unstable at the moment in comparison to my experiences with etcd, swarm, or cockroachdb.  There are a number of open issues in github right now related to database errors and quorum loss.  _update: post v3.20, I've had much better experiences_

Kernel parameters required by contained applications must be managed on the physical host, requiring coordination between whoever is running the cluster and whoever is running the applications.

As we are running all other services on top of lxd, is is very important not to create any dependency loops in the case of a disaster.  For example - I run a local mirror of the alpine repos in a minio cluster that runs in lxd containers.  For a while I had the lxd hosts source that local mirror.  This is fine as long as the cluster maintains a quorum, but if the quorum is lost and the mirror can't be booted, then the lxd hosts don't have available repos anymore and things start to fall apart.  Lesson learned: it is wise to use seperate processes for package management on host and virtual infrastructure.
