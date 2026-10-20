#!/bin/bash
set -euo pipefail

if [ "$1" != "execute" ]; then
    ### executing in the host machine ###

    COPADO_DOCKER_NAME=${COPADO_DOCKER_NAME:-copadodocker}
    COPADO_DOCKER_DIR=${COPADO_DOCKER_DIR:-images}
    COPADO_ENV_FILE=${2:-local/run.env}

    echo "#RUNSH# building image $COPADO_DOCKER_NAME"
    case `uname` in
        Darwin)
            docker buildx build --platform linux/amd64 -t "$COPADO_DOCKER_NAME" "$COPADO_DOCKER_DIR"
        ;;
        *)
            docker build -t "$COPADO_DOCKER_NAME" "$COPADO_DOCKER_DIR"
        ;;
    esac

    echo
    echo "#RUNSH# executing $1 using the parameters in $COPADO_ENV_FILE"

    docker run --rm --env-file "$COPADO_ENV_FILE" -e CF_NAMESPACE=copado__ \
        $(if [ `uname` = "Darwin" ]; then echo "--platform linux/amd64"; fi) \
        --memory=2gb --memory-swap=0 \
        --mount type=bind,source="$(pwd)",target=/t \
        "$COPADO_DOCKER_NAME" bash /t/local/run.sh execute "$1" 2>&1 | tee output.txt
    exit 0
fi

### executing inside docker ###

# set the PATH so copado, copado-git-get or other mocked commands are available first in the path
if [[ -n "${COPADO_LOCAL_FIRST_IN_PATH:-}" ]]; then
    export PATH="/t/local:$PATH" # find commands first in /t/local, allowing mocking
else
    export PATH="$PATH:/t/local" # find commands first anywhere but in /t/local
fi

# NOTE: use the correct interpreter for the functions: bash, node, python, depending on the file extension
case "$2" in
    *.sh) bash "/t/$2" ;;
    *.js) node "/t/$2" ;;
    *.py) python "/t/$2" ;;
    *)
        echo "Unsupported function file: $2" >&2
        exit 2
        ;;
esac
