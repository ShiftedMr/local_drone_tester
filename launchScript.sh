#! /usr/bin/env bash
# Bail from script if any command fails
set -e
localenvpath=".localenv"
. ./.instantiate.sh ${localenvpath}
. ./${localenvpath} # source the localenv vile created by instantiate
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEFAULTUSER="shiftedmr"
DRONESERVNAME="localdrone"
DRONERUNNAME="local-drone-runner-1"
DOCKERNETWORK="localdronenet"
GITEASRVNAME="localgitea"
dserverrunning=$(docker ps -f "name=${DRONESERVNAME}" --format '{{.Names}}'|wc -l)
drunrunning=$(docker ps -f "name=${DRONERUNNAME}" --format '{{.Names}}'|wc -l)
dnetExist=$(docker network list -f name=${DOCKERNETWORK} --format "{{.Name}}"|wc -l)
gitearunning=$(docker ps -f "name=${GITEASRVNAME}" --format '{{.Names}}'|wc -l)
#Docker bridge network

[ -d "${SCRIPT_DIR}/volumes" ] || mkdir "${SCRIPT_DIR}/volumes"

if [[ "0" -eq "${dnetExist}" ]]
then
  echo "creating docker network for drone"
  docker network create ${DOCKERNETWORK}
else
  echo "using existing docker bridge network for local drone"
fi

#gitea
if [[ "${gitearunning}" -eq "0" ]]
then
  echo "Starting up gitea server"
  docker run \
    -it --network="${DOCKERNETWORK}" --name=${GITEASRVNAME} \
    --env=USER_UID=1000 \
    --env=USER_GID=1000 \
    --detach=true \
    --publish=222:22 \
    --publish=3001:3001 \
    --volume=${SCRIPT_DIR}/volumes/giteavol:/data \
    --volume=/etc/timezone:/etc/timezone:ro \
    --volume /etc/localtime:/etc/localtime:ro \
    --volume="${SCRIPT_DIR}/gitea/giteaconfig.ini:/data/gitea/conf/app.ini"\
    fredtest:latest 
  echo "Creating gitea admin"
  sleep 20
  docker exec -u git -i localgitea sh -c "gitea admin user create --username ${DEFAULTUSER} --password supersecret --email haha@no.com --access-token --must-change-password=false" &> output
  rslt="$(cat output)"
  echo "rslt: ${rslt}"
  admin_user_token=$(echo "${rslt}"|grep "Access token" | awk -F "created... " '{print $2}')
  echo "creating drone oauth app in gitea"
  jsonbody='{"Name":"localdrone","redirect_uris":["http://--DRONE--/login"]}'
  oauth_app_json_blob=$(curl -d"${jsonbody/--DRONE--/${DRONESERVNAME}}" -H"Content-type: application/json"  -H "Authorization: Bearer ${admin_user_token}" ${GITEASRVNAME}:3001/api/v1/user/applications/oauth2)
  export DRONE_GITEA_CLIENT_ID=$(echo "${oauth_app_json_blob}" | jq '.client_id' | sed 's/"//g')
  export DRONE_GITEA_CLIENT_SECRET=$(echo "${oauth_app_json_blob}" | jq '.client_secret' | sed 's/"//g')
  echo "DRONE_GITEA_CLIENT_ID ${DRONE_GITEA_CLIENT_ID}"
  echo "DRONE_GITEA_CLIENT_SECRET ${DRONE_GITEA_CLIENT_SECRET}"
  echo "Creating repo drone_test_world"
   curl -d'{"name":"drone_test_world","default_branch":"main"}' \
   -H "Authorization: Bearer ${admin_user_token}" \
   -H"Content-Type: application/json" ${GITEASRVNAME}:3001/api/v1/user/repos

else
  echo "gitea already running"
fi

# running drone server
if [[ "${dserverrunning}" -eq "0" ]]
then
  echo "drone server isn't running. Starting it now"
  docker run \
    --network="${DOCKERNETWORK}"\
    --volume="${SCRIPT_DIR}/volumes/drone:/data" \
    --env=DRONE_GITEA_CLIENT_ID=${DRONE_GITEA_CLIENT_ID} \
    --env=DRONE_GITEA_CLIENT_SECRET=${DRONE_GITEA_CLIENT_SECRET} \
    --env=DRONE_GITEA_SERVER=http://${GITEASRVNAME}:3001 \
    --env=DRONE_SERVER_PROTO=${DRONEURIPROTO} \
    --env=DRONE_SERVER_HOST=${DRONESERVNAME} \
    --env=DRONE_RUNNER_CAPACITY=2 \
    --env=DRONE_USER_CREATE=username:${DEFAULTUSER},admin:true \
    --publish=80:80 \
    --publish=443:443 \
    --restart=always \
    --detach=true \
    --name=${DRONESERVNAME} \
    drone/drone:2.11.1
else
  echo "drone server is already running. Skipping start"
fi
echo "here"
# running drone runner docker
if [[ "${drunrunning}" -eq "0" ]]
then
  echo "drone runner isn't running. Starting it now"
  docker run --detach=true \
    --network="${DOCKERNETWORK}"\
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
else
  echo "drone runner is already running. Skipping start"
fi
