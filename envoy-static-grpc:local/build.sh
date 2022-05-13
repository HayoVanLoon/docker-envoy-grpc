#!/usr/bin/env bash

# Copyright 2022 Hayo van Loon
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eo pipefail

IMAGE_NAME="envoy-static-grpc:local"

LISTENER_PORT=10000
SVCS=
ENDPOINT_PORT=8080

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - build an image for a gRPC-json proxy to a local service

${B}SYNOPSIS${X}
    ${0}  [--lp LISTENER_PORT] [--ep ENDPOINT_PORT] [--image-name IMAGE_NAME] SERVICE_NAME [SERVICE_NAME...]

${B}DESCRIPTION${X}
    Builds an image with a static gRPC config.

    ${B}--lp${X} LISTENER_PORT
        Port proxy will be listening on. Defaults to 10000

    ${B}--ep${X} ENDPOINT_PORT
        Port proxy will be forwarding to. Defaults to 8080

    ${B}--image-name${X} IMAGE_NAME
        Name to use for image. Defaults to ${IMAGE_NAME}

${B}EXAMPLES${X}
    ${B}${0} helloworld.Greeter${X}

    Build an image that with minimal parameter set.

    ${B}${0} --lp 10000 --ep 8080 helloworld.Greeter${X}

    Build an image that will listen on port 10000 and forward to port 8080.
"
}

while true; do
	case ${1} in
	--lp)
		LISTENER_PORT=${2}
		shift 2
		;;
	--ep)
		ENDPOINT_PORT=${2}
		shift 2
		;;
	--image-name)
		IMAGE_NAME=${2}
		shift 2
		;;
	--help)
		usage
		exit 0
		;;
	'')	break ;;
	*)
		SVCS="$([ -n "${SVCS}" ] && echo "${SVCS}, " || echo "")\"${1}\""
		shift 1
		;;
	esac
done

docker build \
	--build-arg LISTENER_PORT=${LISTENER_PORT} \
	--build-arg SERVICES="${SVCS}" \
	--build-arg ENDPOINT_PORT=${ENDPOINT_PORT} \
	-t ${IMAGE_NAME} .
