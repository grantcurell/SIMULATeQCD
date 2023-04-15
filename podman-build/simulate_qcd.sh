#!/bin/bash

scriptdir=$(cd $(dirname $0); pwd)
topdir=$(cd $scriptdir/../; pwd)
cd $topdir

if [[ $(id -u) = 0 ]]; then
  echo "Please do not run $(basename $0) as root, it is designed to be run as a normal user account that has podman permissions."
  exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo 'No arguments provided. Run with -h for help.'
    exit 0
fi

touch $topdir/podman-build/container-info-simulateqcd.txt 

check_redpanda_is_running() { # TODO - do I need this?
  if [[ -z $(docker inspect --format '{{.State.Running}}' simulateqcd | grep -i true) ]]; then
      echo  "It appears that the simulateqcd container is not running. Make sure you have first run 'redpanda setup' before running this command. This command uses 'docker inspect --format '{{.State.Running}}' simulateqcd | grep -i true' to test Redpanda's status."
      exit 1
  fi
}

# This function parses a YAML file and converts it to a Bash script.
# Parameters:
#  $1: The path to the YAML file to parse
#  $2: The prefix to use for Bash variable names
#
# The expected output of this function is a series of Bash variable
# declarations, based on the contents of the input YAML file. For example if
# your YAML file contains 'RHEL_VERSION: 9', this would produce 
# CONFIG_RHEL_VERSION="9"
# Original code taken from: https://stackoverflow.com/a/21189044/4427375
function parse_yaml {
    local prefix=$2
    # Define regular expressions to match various parts of YAML syntax
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs=$(echo @|tr @ '\034')
    # Use sed to replace various parts of the YAML with Bash syntax
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
    # Use awk to create Bash variables based on the YAML data
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {
            if (i > indent) {
                delete vname[i]
            }
        }
        if (length($3) > 0) {
            vn="";
            for (i=0; i<indent; i++) {
                vn=(vn)(vname[i])("_")
            }
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
        }
    }'
}

BUILD_ARG=
DETACH_ARG="-d"
DEBUG_ARG=""
DEBUG_ENV=""

opts=$(getopt \
  -n $(basename $0) \
  -o h \
  --longoptions "build" \
  --longoptions "detach" \
  --longoptions "nodetach" \
  --longoptions "verbose" \
  --longoptions "debug" \
  -- "$@")
if [[ $? -ne 0 ]]; then
  opts="-h"
  echo
fi

eval set -- "$opts"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h)
      echo "Usage:  $(basename $0) (start|stop|setup|[day command]|run [command]|status|logs [target]) [--build]"
      echo
      echo "Args:"
      echo "  build       Build SIMULATeQCD from source"
      echo "  list        Lists all the possible build targets"
      echo
      echo "Flags:"
      echo "  --build    (Re-)build the containers from source"
      echo "  --verbose    Applies to any day commands. Under the hood this will run ansible-playbook with verbose flags."
      echo "  --debug    Runs the application in debug mode. TODO - add what this does"
      echo
      echo
      echo "Start options:"
      echo "  --detach|--nodetach   Either detach (default) from docker compose or stay attached and view debug"
      exit 0
      ;;
    --detach)
      DETACH_ARG="-d"
      ;;
    --nodetach)
      echo "User requested we do not detach from containers."
      DETACH_ARG=""
      ;;
    --verbose)
      VERBOSE="-vvv"
      ;;
    --)
      shift
      break
      ;;
  esac
  shift
done

# Check if user inadvertently enabled podman as root
if systemctl is-enabled podman podman.socket; then
  echo "It looks like you are running podman as root. You will need to disable this before continuing with 'systemctl disable --now podman podman.socket'"
  exit
fi

# Check if podman is installed
if ! which podman; then
  echo "You need to install podman to continue."
  exit
fi

# Enable podman for user if it isn't already on with the remote socket present
# The test checks if the socket for podman exists. Use -e because it isn't a 
# regular file.
if ! test -e $(podman info --format '{{.Host.RemoteSocket.Path}}'); then
  echo "podman service for user not enabled. Running 'systemctl enable --now --user podman podman.socket'"
  systemctl enable --now --user podman podman.socket
fi

# Export docker host and set it to the filepath of podman's socket
export DOCKER_HOST=unix://$(podman info --format '{{.Host.RemoteSocket.Path}}')

# Make container user UID match calling user so that containers dont leave droppings we cant remove
USER_ID=$(id -u)
GROUP_ID=$(id -g)
USERNAME=simulateqcd
GROUPNAME=simulateqcd

echo "Group ID: ${GROUP_ID}"
echo "User ID: ${USER_ID}"

# Check how many physical cores are available. Only run if CORES is not set
if [ -z "$CORES" ]; then
    CORES=$(grep -c ^processor /proc/cpuinfo)

    # Output the number of physical cores found
    echo "Found ${CORES} physical cores."
fi

# Call parse_yaml to create Bash variables from the YAML file
eval "$(parse_yaml "$scriptdir/config.yml")"

# Read in the YAML file
echo "RHEL_VERSION=$RHEL_VERSION"
echo "CUDA_VERSION=$CUDA_VERSION"
RHEL_VERSION=$RHEL_VERSION
CUDA_VERSION=$CUDA_VERSION

case $1 in
  rm)
    podman rm simulateqcd
    ;;

  list)

      # This function captures all the possible build targets from the CMakeLists.txt file

      # Define the regular expression to match lines with format
      # add_SIMULATeQCD_executable(memManTest src/testing/main_memManTest.cpp)
      # The capture group ([[:alnum:]_]+) matches one or more alphanumeric characters 
      # or underscores. The rest is a literal string.
      regex='add_SIMULATeQCD_executable\(([[:alnum:]_]+)'

      # Find all matching lines in the CMakeLists.txt file
      matches=$(grep -oE "$regex" $scriptdir/CMakeLists.txt)

      # Extract the capture group from each match and add it to the list
      list=()
      while read -r match; do
        if [[ $match =~ $regex ]]; then
          list+=("${BASH_REMATCH[1]}")
        fi
      done <<< "$matches"

      # Sort the resulting list alphabetically
      sorted_list=($(echo "${list[@]}" | tr ' ' '\n' | sort))

      # Print the resulting sorted list
      printf '%s\n' "${sorted_list[@]}"

    ;;

  build)

      # Enable the podman service for the user if it isn't already on
      systemctl enable --now --user podman podman.socket

      # Delete any old containers still running on the server
      for container in simulateqcd
      do
        id=$(podman container ls -a --filter name=$container -q)
        if [[ -z $id ]]; then
          continue
        fi
        echo "Cleaning up old containers for $container: $id"
        echo -n "Stopping: "
        podman container stop $id
        echo -n "Removing: "
        podman container rm -v $id
      done

      # Check that the CUDA_VERISON is set and valid
      url="https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/"

      # Get the page content and filter for lines containing "cuda-toolkit"
      content=$(curl -s "$url" | grep "cuda-toolkit")

      # Parse the content for versions and filter out the ones containing "config"
      versions=$(echo "$content" | sed -nE 's/.*cuda-toolkit-[0-9]+-[0-9]+-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+).*/\1/p' | grep -v "config" | uniq)

      # Check if CUDA_VERSION is set
      if [ -z "$CUDA_VERSION" ]; then
          echo "Please set the CUDA_VERSION environment variable."
          exit 1
      fi

      # Check if the provided version is valid
      if echo "$versions" | grep -q "^${CUDA_VERSION}-[0-9]\+$"; then
          echo "The provided CUDA toolkit version ($CUDA_VERSION) is valid."
      else
          echo "The provided version ($CUDA_VERSION) is not valid. Please choose a valid version from the list:"
          echo "$versions" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)-[0-9]+/\1/'
          exit 1
      fi

      #export BUILDKIT_PROGRESS=plain
      echo "Running: podman build \
--tag simulateqcd/simulateqcd:latest \
--label name=simulateqcd \
--build-arg CORES=${CORES} \
--build-arg RHEL_VERSION=${RHEL_VERSION} \
--build-arg CUDA_VERSION=${CUDA_VERSION} \
--build-arg USERNAME=${USERNAME} \
--build-arg GROUPNAME=${GROUPNAME} \
--build-arg USER_ID=${USER_ID} \
--build-arg GROUP_ID=${GROUP_ID} \
--build-arg ARCHITECTURE=${ARCHITECTURE} \
--build-arg USE_GPU_AWARE_MPI=${USE_GPU_AWARE_MPI} \
--build-arg USE_GPU_P2P=${USE_GPU_P2P} \
--build-arg TARGET=${TARGET} \
-f $scriptdir/Dockerfile
$topdir"

      podman build \
        --tag simulateqcd/simulateqcd:latest \
        --label name=simulateqcd \
        --build-arg CORES=${CORES} \
        --build-arg RHEL_VERSION=${RHEL_VERSION} \
        --build-arg CUDA_VERSION=${CUDA_VERSION} \
        --build-arg USERNAME=${USERNAME} \
        --build-arg GROUPNAME=${GROUPNAME} \
        --build-arg USER_ID=${USER_ID} \
        --build-arg GROUP_ID=${GROUP_ID} \
        --build-arg ARCHITECTURE=${ARCHITECTURE} \
        --build-arg USE_GPU_AWARE_MPI=${USE_GPU_AWARE_MPI} \
        --build-arg USE_GPU_P2P=${USE_GPU_P2P} \
        --build-arg TARGET=${TARGET} \
        -f $scriptdir/Dockerfile
        $topdir

      # Remove dangling images (images that are not tagged)
      #podman rmi $(podman images -f "dangling=true" -q)

      # TODO - need to update this
      echo "Checking if the server is running..."

      if [[ -z $(podman inspect --format '{{.State.Running}}' simulateqcd | grep -i true) ]]; then
          echo  "It appears that the SIMULATeQCD (simulateqcd) container failed to deploy correctly. Try checking its status with 'podman logs simulateqcd'."
          exit 1
      fi

      # TODO - need to update this
      echo "The build has finished and Patches is running as expected!"
      ;;  

  *)
    echo "Run $(basename $0) build to build SIMULATeQCD."
    exit 1
    ;;
esac
