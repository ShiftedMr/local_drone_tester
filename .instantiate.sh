#!/usr/bin/env bash
localenvpath="$1"
if [ -f "$localenvpath" ]; then
    echo "$localenvpath exists. Will not generate a new one"
else 
    echo "$localenvpath does not exist; setting up a new environment file."
    echo "What username will you be using for git?:(default:shiftedmr) "
    read input
    gituser=${input:-"shiftedmr"}
    echo "Port for working with gitea? (default conflicts with runner new default:3001)"
    read input
    giteaport=${input:-"3001"}
    echo "Hostname for working with gitea? (default:localgitea.local)"
    read input
    giteahost=${input:-"localgitea.local"}
    echo "local drone address? (default localdrone.local)"
    read input
    dronehost=${input:-"localdrone.local"}
    echo "export LOCAL_DRONE_SECRET=$(openssl rand -hex 16)
    export GITUSER=${gituser}
    export GITEAHOST=${giteahost}
    export GITEAPORT=${giteaport}
    export DRONEHOST=${dronehost}" > ${localenvpath}
fi
