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

SCRIPT_ID="local"
ENVOY_VERSION=v1.25

SVCS=

IMAGE_NAME="envoy-static-grpc:local"
DESCRIPTOR="descriptor.pb"
DEBUG=
LISTENER_PORT="10000"
ENDPOINT_ADDRESS="localhost"
ENDPOINT_PORT="8080"

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - build an image for a gRPC-json proxy to a local service

${B}SYNOPSIS${X}
    ${0} [--image-name IMAGE_NAME] [-d DESCRIPTOR] [--debug] [--lp LISTENER_PORT] [--endpoint-port ENDPOINT_PORT] SERVICE_NAME [SERVICE_NAME...]

${B}DESCRIPTION${X}
    Builds an image with a static gRPC config.

	${B}--image-name${X} IMAGE_NAME
        Name to use for image. Defaults to '${IMAGE_NAME}'.

	${B}-d|--descriptor${X} DESCRIPTOR
        gRPC descriptor file. Defaults to '${DESCRIPTOR}'.

	${B}--debug${X}
        Activate debug mode. Debug mode keeps build artefacts.

	${B}--lp${X} LISTENER_PORT
        Default proxy listening port. Defaults to '${LISTENER_PORT}'.

	${B}--endpoint-address${X} ENDPOINT_ADDRESS
        Proxy forwarding address. Defaults to '${ENDPOINT_ADDRESS}'.

	${B}--endpoint-port${X} ENDPOINT_PORT
        Default proxy forwarding port. Defaults to '${ENDPOINT_PORT}'.
"
}

while true; do
	case ${1} in
	--image-name)
		IMAGE_NAME=${2}
		shift 2
		;;
	-d|--descriptor)
		DESCRIPTOR=${2}
		shift 2
		;;
	--debug)
		DEBUG=1
		shift 1
		;;
	--lp)
		LISTENER_PORT=${2}
		shift 2
		;;
	--endpoint-address)
		ENDPOINT_ADDRESS=${2}
		shift 2
		;;
	--endpoint-port)
		ENDPOINT_PORT=${2}
		shift 2
		;;
	--help)
		usage
		exit 0
		;;
	'') break ;;
	*)
		SVCS="$([ -n "${SVCS}" ] && echo "${SVCS}, " || echo "")\"${1}\""
		shift 1
		;;
	esac
done

if [ -z "${SVCS}" ]; then
	echo "Need at least one service"
	exit 3
fi

if [ ! -f "${DESCRIPTOR}" ]; then
	echo "${0}: cannot stat '${DESCRIPTOR}': No such file"
	exit 3
fi

echo "
IMAGE_NAME:       \"${IMAGE_NAME}\"
DESCRIPTOR:       \"${DESCRIPTOR}\"
DEBUG:            \"${DEBUG}\"
LISTENER_PORT:    \"${LISTENER_PORT}\"
ENDPOINT_ADDRESS: \"${ENDPOINT_ADDRESS}\"
ENDPOINT_PORT:    \"${ENDPOINT_PORT}\"
"

BUILD_DIR="tmp/build-${SCRIPT_ID}-$(date +%s)"
mkdir -p "${BUILD_DIR}"

cp "${DESCRIPTOR}" "${BUILD_DIR}"

cat >"${BUILD_DIR}/config.yaml" <<EOF
static_resources:

  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: PLACEHOLDER_LISTENER_PORT
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress
          codec_type: AUTO
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: {prefix: "/"}
                route:
                  cluster: local_service
                  timeout: 90s
                  max_stream_duration:
                    grpc_timeout_header_max: 90s
              typed_per_filter_config:
                envoy.filters.http.cors:
                  "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
                  allow_origin_string_match:
                  - safe_regex: {regex: \*}
                  allow_methods: "OPTIONS, GET, POST, PUT, DELETE, PATCH"
                  allow_headers: "*"
                  expose_headers: "grpc-status grpc-message"
                  allow_credentials: {value: true}
          http_filters:
          - name: envoy.filters.http.grpc_json_transcoder
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_json_transcoder.v3.GrpcJsonTranscoder
              proto_descriptor: "/configs/descriptor.pb"
              services: [ ${SVCS} ]
              request_validation_options:
                reject_unknown_method: true
                reject_binding_body_field_collisions: true
              convert_grpc_status: true
              match_incoming_request_route: true
              auto_mapping: false
          - name: envoy.filters.http.cors
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog

  clusters:
  - name: local_service
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    typed_extension_protocol_options:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        explicit_http_config:
          http2_protocol_options: {}
    load_assignment:
      cluster_name: local_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: PLACEHOLDER_ENDPOINT_ADDRESS
                port_value: PLACEHOLDER_ENDPOINT_PORT
EOF

cat >"${BUILD_DIR}/entrypoint.sh" <<EOF
#!/usr/bin/env bash

set -eo pipefail

echo LISTENER_PORT:    "\${LISTENER_PORT}"
echo ENDPOINT_ADDRESS: "\${ENDPOINT_ADDRESS}"
echo ENDPOINT_PORT:    "\${ENDPOINT_PORT}"

YAML=\$(
	cat /configs/config.yaml | \
		sed "s/PLACEHOLDER_LISTENER_PORT/\${LISTENER_PORT}/g" | \
		sed "s/PLACEHOLDER_ENDPOINT_ADDRESS/\${ENDPOINT_ADDRESS}/g" | \
		sed "s/PLACEHOLDER_ENDPOINT_PORT/\${ENDPOINT_PORT}/g"
)

if [ -n "\${ENVOY_VALIDATE}" ]; then
	envoy --mode validate --config-yaml "\${YAML}"
	exit 0
fi

envoy --config-yaml "\${YAML}"

EOF
chmod +x "${BUILD_DIR}/entrypoint.sh"

################################################################################

cat >"${BUILD_DIR}/Dockerfile" <<EOF
FROM envoyproxy/envoy:${ENVOY_VERSION}-latest

COPY config.yaml /configs/
COPY entrypoint.sh /

ENV ENVOY_VALIDATE=""
ENV LISTENER_PORT="${LISTENER_PORT}"
ENV ENDPOINT_ADDRESS="${ENDPOINT_ADDRESS}"
ENV ENDPOINT_PORT="${ENDPOINT_PORT}"

COPY descriptor.pb /configs/

CMD /entrypoint.sh
EOF

(
	cd "${BUILD_DIR}"
	docker build \
		-t "${IMAGE_NAME}" .
)

[ -z "${DEBUG}" ] && rm -rf "${BUILD_DIR}" || echo "Build artefacts remain in: ${BUILD_DIR}"

echo "Testing container ..."
docker run \
	--env ENVOY_VALIDATE=1 \
	-i -t --rm "${IMAGE_NAME}"
