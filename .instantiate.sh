#!/usr/bin/env bash
localenvpath="$1"
if [ -f "$localenvpath" ]; then
    echo "$localenvpath exists. Will not generate a new one"
else 
    echo "$localenvpath does not exist; setting up a new environment file."
    echo "Please paste your Github app's Client ID for your local drone: "
    read localghid
    echo "Please paste your Github app's Client Secret for your local drone: "
    read localghsecret
    echo "what uri can drone be accessed at?(no protocol)"
    read droneuri
    echo "which protocol? Http/https? (note if you don't have a cert type http)"
    read httproto
    echo "export LOCAL_DRONE_SECRET=$(openssl rand -hex 16)
    export GITHUB_CLIENT_ID=${localghid}
    export GITHUB_CLIENT_SECRET=${localghsecret}
    export DRONEURI=${droneuri}
    export DRONEURIPROTO=${httproto}" > ${localenvpath}
fi
