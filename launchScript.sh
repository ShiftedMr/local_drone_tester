#! /usr/bin/env bash
# Bail from script if any command fails
# uncomment for debug
DEBUG="${SCRIPTDEBUG:-"false"}"
# Arrays must be same length. Syntax is such as this was developed using the old version of bash on stupid osx
declare -a prereq_cmds=( "docker" "jq" "go" "make" )
declare -a prereq_cmds_exist=( 0 0 0 0 )
if [[ "${DEBUG}" == "true" ]]
then
  set -x
fi

debug_output () {
  if [[ "${DEBUG}" != "short" ]]
  then
    echo "$*"
  fi
}

debug_output "Prereq commands docker_exists: ${docker_exists}; jq_exists: ${jq_exists}; go_exists: ${go_exists}; make_exists: ${make_exists};"
debug_output "array: ${prereq_cmds[@]}"
cmdarraylength=${#prereq_cmds[@]}
for (( i=0; i<${cmdarraylength}; i++ ));
do
	debug_output "${prereq_cmds[$i]}"
	debug_output "cmd ${prereq_cmds[$i]}"
  ign_outp=$(type -t ${prereq_cmds[$i]})
  exists=$?
  debug_output "${prereq_cmds[$i]} exists (1 means no)? index $i $(type -t ${exists})"
  prereq_cmds_exist[$i]=$exists
done

missing_cmd="false"
for (( i=0; i<${cmdarraylength}; i++ ));
do
  if [[ "${prereq_cmds_exist[${i}]}" -ne 0 ]]
  then
    echo "cmd ${prereq_cmds[${i}]} is missing"
    missing_cmd="true"
  fi
done

if [[ "${missing_cmd}" == "true" ]]
then
  echo "exiting due to missing prereq commands"
  exit 1
else
  debug_output "All prereq commands were found"
fi

set -e
localenvpath=".localenv"
localgiteaenvpath=".localenv.gitea"
. ./.instantiate.sh ${localenvpath}
. ./${localenvpath} # source the localenv file created by instantiate
. ./${localgiteaenvpath} # source the localenv for gitea in case we're doing a relaunch of drone
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DVNAME="localvalidator.local"
DRONESERVNAME=${DRONEHOST:-"localdrone.local"}
DRONERUNNAME="local-drone-runner-1.local"
DOCKERNETWORK="localdronenet"
GITEASRVNAME=${GITEAHOST:-"localgitea.local"}
LOCAL_DRONE_SECRET=${LOCAL_DRONE_SECRET:-285aa134b2cd18ca2c3046e2b05a63bb}
#local docker image names
GiteaImg="localgitea"
ValidatorImage="localvalidator"
ValidatorPassString="vvv" #validatorpassmeplease

# Variables for Checking if systems are running
dvalidrunning=$(docker ps -f "name=${DVNAME}" --format '{{.Names}}'|wc -l)
dserverrunning=$(docker ps -f "name=${DRONESERVNAME}" --format '{{.Names}}'|wc -l)
drunrunning=$(docker ps -f "name=${DRONERUNNAME}" --format '{{.Names}}'|wc -l)
dnetExist=$(docker network list -f name=${DOCKERNETWORK} --format "{{.Name}}"|wc -l)
gitearunning=$(docker ps -f "name=${GITEASRVNAME}" --format '{{.Names}}'|wc -l)


DRONEURIPROTO="http"
DEFAULTUSER=${GITUSER:-"shiftedmr"}
GITEAPORT=${GITEAPORT:-"3001"}

#Prep

# Make volumes directory if it doesn't exist
[ -d "${SCRIPT_DIR}/volumes" ] || mkdir "${SCRIPT_DIR}/volumes"

#functions for managing services

stopAndRemove () {
  if [[ "$#" -eq "1" ]]
  then
    docker ps -f "name=${1}" --format '{{.Names}}' && docker stop ${1} && docker rm ${1}
  fi
}

makeImage() {
  if [[ "$#" -ne "1" ]]
  then
    return 255
  fi
  image=$1
  docker build -t ${image}:latest "${SCRIPT_DIR}/${image}-builddir/"
}

getImageCount () {
  if [[ "$#" -ne "1" ]]
  then
    return 255
  fi
  imagename=$1
  echo "$(docker images ${imagename} --format "{{.Repository}}"|wc -l)"
}

startValidator() {
  echo "starting validator"
  docker run \
    --network="${DOCKERNETWORK}"\
    --env=DRONE_SECRET=${LOCAL_DRONE_SECRET} \
    --env=DRONE_DEBUG=true \
    --env=DRONE_VALID_PASS_STRING=${ValidatorPassString} \
    --publish=3124:3124 \
    --restart=always \
    --detach=true \
    --name=${DVNAME} \
    ${ValidatorImage}:latest
}

startGitea () {
  echo "Starting up gitea server"
    docker run \
      -it --network="${DOCKERNETWORK}" --name=${GITEASRVNAME} \
      --env=USER_UID=1000 \
      --env=USER_GID=1000 \
      --detach=true \
      --publish=222:22 \
      --publish=${GITEAPORT}:${GITEAPORT} \
      --volume=${SCRIPT_DIR}/volumes/giteavol:/data \
      --volume=/etc/timezone:/etc/timezone:ro \
      --volume /etc/localtime:/etc/localtime:ro \
      --volume="${SCRIPT_DIR}/${GiteaImg}-builddir/giteaconfig.ini:/data/gitea/conf/app.ini"\
      ${GiteaImg}:latest 
    echo "Creating gitea admin"
    sleep 20
    docker exec -u git -i ${GITEASRVNAME} sh -c "gitea admin user create --username ${DEFAULTUSER} --password supersecret --email "haha@no.com" --admin --access-token --must-change-password=false" | tee output
    rslt="$(cat output)"
    echo "rslt: ${rslt}"
    admin_user_token=$(echo "${rslt}"|grep "Access token" | awk -F "created... " '{print $2}')
    echo "creating drone oauth app in gitea"
    jsonbody='{"Name":"localdroneapp","redirect_uris":["http://--DRONE--/login"]}'
    oauth_app_json_blob=$(curl -d"${jsonbody/--DRONE--/${DRONESERVNAME}}" -H"Content-type: application/json"  -H "Authorization: Bearer ${admin_user_token}" ${GITEASRVNAME}:${GITEAPORT}/api/v1/user/applications/oauth2)
    export DRONE_GITEA_CLIENT_ID=$(echo "${oauth_app_json_blob}" | jq '.client_id' | sed 's/"//g')
    export DRONE_GITEA_CLIENT_SECRET=$(echo "${oauth_app_json_blob}" | jq '.client_secret' | sed 's/"//g')
    echo "DRONE_GITEA_CLIENT_ID ${DRONE_GITEA_CLIENT_ID}"
    echo "DRONE_GITEA_CLIENT_SECRET ${DRONE_GITEA_CLIENT_SECRET}"
    # Sending the gitea client and secret to local env incase drone gets restarted
    echo "export DRONE_GITEA_CLIENT_SECRET=${DRONE_GITEA_CLIENT_SECRET}" > ${localgiteaenvpath}
    echo "export DRONE_GITEA_CLIENT_ID=${DRONE_GITEA_CLIENT_ID}" >> ${localgiteaenvpath}
    echo "export GITEA_ADMIN_TOKEN=${admin_user_token}" >> ${localgiteaenvpath}
    echo "Creating repo drone_test_world"
    curl -d'{"name":"drone_test_world","default_branch":"main"}' \
    -H "Authorization: Bearer ${admin_user_token}" \
    -H"Content-Type: application/json" ${GITEASRVNAME}:${GITEAPORT}/api/v1/user/repos
}

# There isn't a function for rerunning gitea because it is required to exist before the rest of everything

startDroneRunner() {
  echo "Starting Drone Runner"
  docker run --detach=true \
    --network="${DOCKERNETWORK}"\
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --env=DRONE_RPC_PROTO=${DRONEURIPROTO} \
    --env=DRONE_RPC_HOST=${DRONESERVNAME} \
    --env=DRONE_RPC_SECRET=${LOCAL_DRONE_SECRET} \
    --env=DRONE_RUNNER_CAPACITY=2 \
    --env=DRONE_RUNNER_NAME=${DRONERUNNAME} \
    --env=DRONE_RUNNER_NETWORKS="${DOCKERNETWORK}" \
    --publish=3000:3000 \
    --restart=always \
    --name=${DRONERUNNAME} \
    drone/drone-runner-docker:1
}

startDroneServer() {
  echo "Starting Drone Server"
  docker run \
      --network="${DOCKERNETWORK}"\
      --volume="${SCRIPT_DIR}/volumes/drone:/data" \
      --env=DRONE_GITEA_CLIENT_ID=${DRONE_GITEA_CLIENT_ID} \
      --env=DRONE_GITEA_CLIENT_SECRET=${DRONE_GITEA_CLIENT_SECRET} \
      --env=DRONE_GITEA_SERVER=http://${GITEASRVNAME}:${GITEAPORT} \
      --env=DRONE_RPC_SECRET=${LOCAL_DRONE_SECRET} \
      --env=DRONE_SERVER_PROTO=${DRONEURIPROTO:-"http"} \
      --env=DRONE_SERVER_HOST=${DRONESERVNAME} \
      --env=DRONE_RUNNER_CAPACITY=2 \
      --env=DRONE_USER_CREATE=username:${DEFAULTUSER},admin:true \
      --env=DRONE_VALIDATE_PLUGIN_ENDPOINT=http://${DVNAME}:3124 \
      --env=DRONE_VALIDATE_PLUGIN_SECRET=${LOCAL_DRONE_SECRET} \
      --env=DRONE_USER_CREATE=username:${DEFAULTUSER},machine:false,admin:true,token:55f24eb3d61ef6ac5e83d550178638dc \
      --publish=80:80 \
      --publish=443:443 \
      --restart=always \
      --detach=true \
      --name=${DRONESERVNAME} \
      drone/drone:2.11.1
}

# Commands

# stopping and removing images
if [[ "$#" -gt "0" ]] && [[ "$1" == "stop" ]]
then
  stopAndRemove ${DRONESERVNAME}
  stopAndRemove ${DRONERUNNAME}
  stopAndRemove ${DVNAME}
  stopAndRemove ${GITEASRVNAME}
  if [[ "$2" == "vols" ]]
  then
    [ -d "${SCRIPT_DIR}/volumes/giteavol" ] && rm -rf "${SCRIPT_DIR}/volumes/giteavol"
    [ -d "${SCRIPT_DIR}/volumes/drone" ] && rm -rf "${SCRIPT_DIR}/volumes/drone"
  fi
  exit 0
fi

# build local docker images
if [[ "$#" -gt "0" ]] && [[ "$1" == "build" ]]
then
  echo "building images"
  makeImage ${GiteaImg}
  cd ${SCRIPT_DIR}/${ValidatorImage}-builddir/
  make build
  cd ${SCRIPT_DIR}
  makeImage ${ValidatorImage}
  exit 0
fi


# rebuild and relaunch validator
if [[ "$#" -gt "1" ]] && [[ "$1" == "rebuild" ]] && [[ "$2" == "validator" ]]
then
  cd ${SCRIPT_DIR}/${ValidatorImage}-builddir/
  make build
  cd ${SCRIPT_DIR}
  makeImage ${ValidatorImage}
  if [[ "${dvalidrunning}" -gt "0" ]]
  then
    stopAndRemove ${DVNAME}
  fi
  if [[ "${dvalidrunning}" -eq "0" ]]
  then
    startValidator
  else
    echo "validator didnt die"
  fi
  exit 0
fi

# build local docker images if they haven't been built
if [[ "$#" -eq "0" ]]
then
  giteaimagecount=$(getImageCount ${GiteaImg})
  validatorimagecount=$(getImageCount ${ValidatorImage})
  if [[ "${giteaimagecount}" -eq "0" ]]
  then
    makeImage ${GiteaImg}
  fi
  if [[ "${validatorimagecount}" -eq "0" ]]
  then
    cd ${SCRIPT_DIR}/${ValidatorImage}-builddir/
    make build
    cd ${SCRIPT_DIR}
    makeImage ${ValidatorImage}
  fi
fi

if [[ "$#" -gt "0" ]]
then
  echo "More parameters than expected/unexpected parameter"
  exit 1
fi


#Docker bridge network
if [[ "0" -eq "${dnetExist}" ]]
then
  echo "creating docker network for drone"
  docker network create ${DOCKERNETWORK}
else
  echo "using existing docker bridge network for local drone"
fi

#gitea local server
if [[ "${gitearunning}" -eq "0" ]]
then
  if [[ ! -f "${SCRIPT_DIR}/${GiteaImg}-builddir/giteaconfig.ini" ]]
    then
      echo "Generating configs from template file for gitea"
      cat "${SCRIPT_DIR}/gitea/giteaconfig.tmpl.ini" | sed "s/%PORT%/${GITEAPORT}/g; s/%GITEAHOST%/${GITEASRVNAME}/g;" > "${SCRIPT_DIR}/gitea/giteaconfig.ini"
    else
    echo "Existing gitea config found."
  fi
  echo "Gitea is not running yet."
  startGitea
else
  echo "gitea already running"
fi


#running validator
if [[ "${dvalidrunning}" -eq "0" ]]
then
  echo "drone validator isn't running. Starting it now"
  startValidator
else
  echo "drone valid is already running. Skipping start"
fi

# running drone server
if [[ "${dserverrunning}" -eq "0" ]]
then
  echo "drone server isn't running."
  startDroneServer
else
  echo "drone server is already running. Skipping start"
fi
echo "here"
# running drone runner docker
if [[ "${drunrunning}" -eq "0" ]]
then
  echo "drone runner isn't running."
  startDroneRunner
else
  echo "drone runner is already running. Skipping start"
fi
