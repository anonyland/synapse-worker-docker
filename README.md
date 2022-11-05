# Synapse Worker Docker

A docker image for synapse workers based off [Synapse-Docker](https://github.com/tommytran732/Synapse-Docker/).

This is designed for users using Synapse inside of docker and wish to use workers.


It would be advisable to use this in conjunction with Synapse-Docker.

Uses alpine as the base images, features a hardened memory allocator and has mjonir support.

## Building

``
git clone https://git.anonymousland.org/anonymousland/synapse-worker-docker/
``

``
cd synapse-worker-docker
``

``
docker build .
``

## Links

- [Synapse Docker](https://github.com/matrix-org/synapse/tree/develop/docker)

- [Docker Compose Workers](https://github.com/matrix-org/synapse/tree/develop/contrib/docker_compose_workers)