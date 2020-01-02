## HAproxy Service Discovery and Docker Swarm

Name-based service discovery using HAproxy and docker swarm.

### docker

Enables reproducable, isolated web application development and deployment.

Web applications and their underlying operating systems can be abstracted to a single `Dockerfile`:

```
# start with a fresh installation of alpine linux
FROM alpine:edge

# install our web app
RUN apk add trac --no-cache

# insert our configuration file
COPY trac.ini .

# initalize the app's directory layout
RUN trac-admin /opt/trac initenv --config=trac.ini

# open a network port
EXPOSE 80

# start the application
ENTRYPOINT [ "tracd", "--env-parent-dir=/opt/" ]
```

A docker "container" runs in an isolated environment, unaware of any other processes, users, containers, data, etc on the host server.  Therefore, we can run n containers on a single server without much management overhead.  We can run as many containers as we have network ports and physical resources.  (utilization is a good thing!)

```
cd ~/docker-apps/trac/trac
docker build .
docker run -p 8000:80 caf8cf7fac42
```

### docker compose

Automates the complicated "-p 8000:80 caf8cf7fac42" portion of the generic docker command, and lets us define runtime "policy" such as port numbers, logging options, etc.

```
version: '3.5'

services:
  trac:
    image: 7f83-docker-registry:5000/trac
    build: ./trac
    ports:
      - 4000:80
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '1'
          memory: '50M'
```

```
cd ~/docker-apps/trac
docker-compose -f ./common.yml build
docker-compose -f ./common.yml -f ./dev.yml up
```

### docker swarm

Enables automated deployment and management of many containers across a cluster of many "dumb" docker nodes.  These nodes are near-identical clones, and have absolute minimal configuration.  Swarm effectively abstracts "applications" from underlying "servers".

Deploying a "stack" to swarm:

```
cd ~/docker-apps/trac/
docker stack deploy -c ./common.yml -c ./dev.yml trac-dev
```

```
docker stack ls
```

```
docker service ls
docker service ps trac-dev_trac
docker service logs -f trac-dev_trac
```

The cluster is indifferent to the loss of nodes:

```
ssh root@9077-vmm
vm list
vm poweroff 9a29-swarm
exit
ssh root@10.0.0.44
docker node ls
docker node demote 9a29-swarm
docker node rm 9a29-swarm
```

### Mapping Application urls to Ports with HAproxy

HAproxy can inspect incoming traffic for the requested URL, and forward traffic accordingly:

```
frontend http_internal
    bind 10.0.0.39:80
    mode http

    use_backend trac-dev        if { hdr(host) -i trac-dev.aec7.from.io }

###

backend trac-dev
    mode http
    balance     roundrobin
    server      app1 10.0.0.40:4000 check
    server      app2 10.0.0.41:4000 check
    server      app3 10.0.0.42:4000 check
    server      app4 10.0.0.43:4000 check
    server      app5 10.0.0.44:4000 check
```

We can bind different "frontends" to different IP addresses, networks, and thus can apply different network policy to different backends:

```
frontend dmz
    bind 10.0.0.38:80
    mode http

    use_backend mkdocs          if { hdr(host) -i aec7.from.io }
    use_backend trac-dmz        if { hdr(host) -i trac.example.com }

frontend http_internal
    bind 10.0.0.39:80
    mode http

    use_backend kibana          if { hdr(host) -i kibana.aec7.from.io }
    use_backend kibana-dev      if { hdr(host) -i kibana-dev.aec7.from.io }
```

SSL too:

```
frontend https_internal
    bind 10.0.0.39:443
    mode tcp

    tcp-request inspect-delay 5s
    tcp-request content accept  if { req_ssl_hello_type 1 }

    use_backend ssl-app         if { req.ssl_sni -i tls.aec7.from.io }
```

With git and ansible, our haproxy configs are version controlled, peer reviewed, and in sync:

```
root@0e54-ws:~/cfg/roles/swarm_ingress # tree
.
|-- handlers
|   `-- main.yml
|-- tasks
|   `-- main.yml
`-- templates
    |-- haproxy.cfg
    `-- keepalived.conf

3 directories, 4 files
```
