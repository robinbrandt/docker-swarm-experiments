#!/bin/bash

DOCKER_MACHINE_PROVIDER=vmwarefusion

checkvm() {
    local vm=$1
    docker-machine ls | grep "$1"
}

# create consul discovery backend

checkvm mh-keystore || docker-machine create -d $DOCKER_MACHINE_PROVIDER mh-keystore
docker-machine start mh-keystore

CONSUL_IP=$(docker-machine ip mh-keystore)

# start consul as discovery backend

eval "$(docker-machine env mh-keystore)"

docker run --restart=always -d -p 8500:8500 --name=consul progrium/consul -server -bootstrap

# start swarm master

checkvm swarm-master || docker-machine create -d $DOCKER_MACHINE_PROVIDER  \
    --engine-opt="cluster-store=consul://$CONSUL_IP:8500" \
    --engine-opt="cluster-advertise=eth0:2376" \
    swarm-master

docker-machine start swarm-master

MASTER_IP=$(docker-machine ip swarm-master)

eval "$(docker-machine env swarm-master)"

docker run --restart=always -d -p 3376:3376 -t -v /var/lib/boot2docker:/certs:ro \
    swarm manage -H 0.0.0.0:3376 --advertise :3376 --tlsverify --tlscacert=/certs/ca.pem --tlscert=/certs/server.pem --tlskey=/certs/server-key.pem consul://$CONSUL_IP:8500

# start swarm node

checkvm swarm-node || docker-machine create -d $DOCKER_MACHINE_PROVIDER \
    --engine-opt="cluster-store=consul://$CONSUL_IP:8500" \
    --engine-opt="cluster-advertise=eth0:2376" \
    swarm-node

docker-machine start swarm-node

NODE_IP=$(docker-machine ip swarm-node)

eval "$(docker-machine env swarm-node)"

docker run -d --restart=always \
    swarm join --addr=$NODE_IP:2376 consul://$CONSUL_IP:8500

# create overlay network

export DOCKER_HOST=$MASTER_IP:3376
(docker network ls | grep swarm-network) || docker network create swarm-network


