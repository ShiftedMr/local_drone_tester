#! /usr/bin/env bash
# Bail from script if any command fails
set -e
localenvpath=".localenv"
. ./.instantiate.sh ${localenvpath}
. ./${localenvpath} # source the localenv vile created by instantiate

DRONESERVNAME="drone"
DRONERUNNAME="local-drone-runner-1"
DOCKERNETWORK="localdrone"
dserverrunning=$(docker ps -f "name=${DRONESERVNAME}" --format '{{.Names}}'|wc -l)
drunrunning=$(docker ps -f "name=${DRONERUNNAME}" --format '{{.Names}}'|wc -l)
dnetExist=$(docker network list -f name=localdrone --format "{{.Name}}"|wc -l)

#Docker bridge network
if [[ "0" -eq "${dnetExist}" ]]
then
  echo "creating docker network for drone"
  docker network create ${DOCKERNETWORK}
else
  echo "using existing docker bridge network for local drone"
fi

# running drone server
if [[ "${dserverrunning}" -eq "0" ]]
then
  echo "drone server isn't running. Starting it now"
  docker run \
    --volume=/var/lib/drone:/data \
    --env=DRONE_GITHUB_SERVER=https://github.com \
    --env=DRONE_GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID} \
    --env=DRONE_GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET} \
    --env=DRONE_RPC_SECRET=${LOCAL_DRONE_SECRET} \
    --env=DRONE_SERVER_PROTO=${DRONEURIPROTO} \
    --env=DRONE_SERVER_HOST=${DRONEURI} \
    --env=DRONE_RUNNER_CAPACITY=2 \
    --env=DRONE_TLS_AUTOCERT=true \
    --env=DRONE_USER_FILTER=shiftedmr \
    --env=DRONE_USER_CREATE=username:shiftedmr,admin:true \
    --publish=80:80 \
    --publish=443:443 \
    --restart=always \
    --detach=true \
    --name=${DRONESERVNAME} \
    drone/drone:2.11.1
  docker network connect ${DOCKERNETWORK} ${DRONESERVNAME}

else
  echo "drone server is already running. Skipping start"
fi
# running drone runner docker
if [[ "${drunrunning}" -eq "0" ]]
then
  echo "drone runner isn't running. Starting it now"
  docker run --detach \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  --env=DRONE_RPC_PROTO=${DRONEURIPROTO} \
  --env=DRONE_RPC_HOST=${DRONESERVNAME} \
  --env=DRONE_RPC_SECRET=${LOCAL_DRONE_SECRET} \
  --env=DRONE_RUNNER_CAPACITY=2 \
  --env=DRONE_RUNNER_NAME=${DRONERUNNAME} \
  --publish=3000:3000 \
  --restart=always \
  --name=${DRONERUNNAME} \
  drone/drone-runner-docker:1
  docker network connect ${DOCKERNETWORK} ${DRONERUNNAME}

else
  echo "drone runner is already running. Skipping start"
fi