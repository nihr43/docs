# HA sshd on kubernetes

_jan 2020_

A highly available sshd bastion service running in kubernetes

---

_rational_

I have an ongoing need for a reliable ssh bastion into a network where a kubernetes cluster runs.  For a while I filled this requirement with a pair of lxd containers each running `sshd`, `keeplived`, `filebeat`, as well as a number of other standard system daemons.  In efforts to simplify the infrastructure overall, eliminating as many components as possible, I have finally gotten around to migrating the service to kubernetes.  Moving sshd from stateful containers to a kubnernetes deployment provides the following benefits:

- three IP addresses are freed
- two less nodes chatting with elasticsearch
- two less instances of keepalived broadcasting on the lan
- ~20 processes total between the two containers replaced with a single sshd process
- no more reason to run duplicates for HA; k8s will replace a failed pod
- two less OS instances to upgrade

---

_implementation_

This Dockerfile is kept as small and simple as possible, landing my github keys in root's `authorized_keys` and disabling all shells.  Though not ideal, the host key is built into the image so when the pod gets reprovisioned I don't get an untrusted host warning.

```
FROM alpine:edge

RUN apk add openssh --no-cache
RUN ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -P '' ;\
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config ;\
    sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/g' /etc/ssh/sshd_config ;\
    passwd -u root ;\
    sed -i 's/\/bin\/ash/\/sbin\/nologin/g' /etc/passwd ;\
    mkdir /root/.ssh ;\
    wget https://github.com/nihr43.keys -O /root/.ssh/authorized_keys

EXPOSE 22
ENTRYPOINT [ "/usr/sbin/sshd", "-D" , "-f", "/etc/ssh/sshd_config" ]
```

I use `terraform` to manage kubernetes resources.  We will need a `deployment`, and a `service` to get traffic to it.  We put the LoadBalancer service on port 2222 so not to conflict with sshd on the host.

```
resource "kubernetes_service" "sshd" {
  metadata {
    name = "sshd"
  }
  spec {
    selector = {
      app = "sshd"
    }
    port {
      port        = "2222"
      target_port = "22"
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment" "sshd" {
  metadata {
    name = "sshd"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "sshd"
      }
    }
    template {
      metadata {
        labels = {
          app = "sshd"
        }
      }
      spec {
        container {
          image = "10.0.0.57:5000/sshd:latest"
          name  = "sshd"
        }
      }
    }
  }
}
```

Now with the image pushed to the registry, and a `terraform apply`, this service is available on port 2222 on all the host nodes and their floating IP.
