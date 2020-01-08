# Rolling Application updates in Docker Swarm

These are notes on the behavior of Docker Swarm while deploying stack updates.  We will learn how Docker behaves by default, and how to achieve high availability during rolling image updates.

Here is the initial stable state our our service:

```
ID                  NAME                      IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
aiylh15qk1uy        rocketchat_rocketchat.1   rocket.chat:0.60    9a4e-swarm          Running             Running 4 minutes ago
kor6b7n1wjfk        rocketchat_rocketchat.2   rocket.chat:0.60    9a29-swarm          Running             Running 19 minutes ago
```

```
git pull
docker stack deploy -c ./common.yml -c ./prod.yml rocketchat
```

After deploying updates to the stack, docker kills one of the replicas and starts downloading the new image:

```
ID                  NAME                          IMAGE               NODE                DESIRED STATE       CURRENT STATE                  ERROR               PORTS
brcbaxpg776u        rocketchat_rocketchat.1       rocket.chat:0.70    9a74-swarm          Running             Preparing about a minute ago
aiylh15qk1uy         \_ rocketchat_rocketchat.1   rocket.chat:0.60    9a4e-swarm          Shutdown            Shutdown about a minute ago
kor6b7n1wjfk        rocketchat_rocketchat.2       rocket.chat:0.60    9a29-swarm          Running             Running 22 minutes ago
```

The download finishes and the container is started:

```
ID                  NAME                          IMAGE               NODE                DESIRED STATE       CURRENT STATE                     ERROR               PORTS
brcbaxpg776u        rocketchat_rocketchat.1       rocket.chat:0.70    9a74-swarm          Running             Starting less than a second ago
aiylh15qk1uy         \_ rocketchat_rocketchat.1   rocket.chat:0.60    9a4e-swarm          Shutdown            Shutdown 8 minutes ago
kor6b7n1wjfk        rocketchat_rocketchat.2       rocket.chat:0.60    9a29-swarm          Running             Running 29 minutes ago
```

Docker prepares to repeat the process on the next replica:

```
ID                  NAME                          IMAGE               NODE                DESIRED STATE       CURRENT STATE                     ERROR               PORTS
brcbaxpg776u        rocketchat_rocketchat.1       rocket.chat:0.70    9a74-swarm          Running             Running less than a second ago
aiylh15qk1uy         \_ rocketchat_rocketchat.1   rocket.chat:0.60    9a4e-swarm          Shutdown            Shutdown 8 minutes ago
wlvjc6lt5ra8        rocketchat_rocketchat.2       rocket.chat:0.70    9a4e-swarm          Ready               Assigned less than a second ago
kor6b7n1wjfk         \_ rocketchat_rocketchat.2   rocket.chat:0.60    9a29-swarm          Shutdown            Running less than a second ago
```

Docker kills the second replica, and starts downloading the image on the next node.  Here we have a problem: our `.2` replica has been killed, but `.1` has only been up for 4 seconds.  Rocketchat in fact takes more than 4 seconds to "boot", especially when database upgrades need performed - which usually takes about 30 seconds.  In this moment, the service is down, and the load balancers are returning `503`.

```
ID                  NAME                          IMAGE               NODE                DESIRED STATE       CURRENT STATE             ERROR               PORTS
brcbaxpg776u        rocketchat_rocketchat.1       rocket.chat:0.70    9a74-swarm          Running             Running 4 seconds ago
aiylh15qk1uy         \_ rocketchat_rocketchat.1   rocket.chat:0.60    9a4e-swarm          Shutdown            Shutdown 8 minutes ago
wlvjc6lt5ra8        rocketchat_rocketchat.2       rocket.chat:0.70    9a4e-swarm          Ready               Preparing 4 seconds ago
kor6b7n1wjfk         \_ rocketchat_rocketchat.2   rocket.chat:0.60    9a29-swarm          Shutdown            Running 4 seconds ago
```

This problem is solved by defining a healthcheck in our compose file:

```
    healthcheck:
      test: curl --fail -s http://localhost:3000/ || exit 1
      interval: 5s
      retries: 2
      start_period: 40s
```

This healthcheck gives rocketchat containers at least 40 seconds to start up, effectively telling the docker daemon to wait a bit before killing replicas.  Now we can perform rolling image updates with zero downtime.
