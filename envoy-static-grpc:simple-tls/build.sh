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

IMAGE_NAME="envoy-static-grpc:simple-tls"
DOCKER_CONTEXT="."
DESCRIPTOR=descriptor.pb

DEBUG=

LISTENER_PORT=10000
SVCS=
ENDPOINT_ADDRESS=

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - build an image for a gRPC-json proxy to a local service

${B}SYNOPSIS${X}
    ${0}  --endpoint-address ENDPOINT_ADDRESS [--lp LISTENER_PORT] [--descriptor DESCRIPTOR] [--image-name IMAGE_NAME] SERVICE_NAME [SERVICE_NAME...]

${B}DESCRIPTION${X}
    Builds an image with a static gRPC config.

    ${B}--lp${X} LISTENER_PORT
        Default proxy listening port. Defaults to 8080.

    ${B}--endpoint-address${X} ENDPOINT_ADDRESS
        Proxy forwarding address. Required.

    ${B}--descriptor{X} DESCRIPTOR
		gRPC descriptor file. Defaults to '${DESCRIPTOR}'.

    ${B}--image-name${X} IMAGE_NAME
        Name to use for image. Defaults to '${IMAGE_NAME}'.

${B}EXAMPLES${X}
    ${B}${0} --endpoint-address www.example.com helloworld.Greeter${X}

    Build an image that with minimal parameter set.
"
}

while true; do
	case ${1} in
	--lp)
		LISTENER_PORT=${2}
		shift 2
		;;
	--endpoint-address)
		ENDPOINT_ADDRESS=${2}
		shift 2
		;;
	--descriptor)
		DESCRIPTOR=${2}
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
	--debug)
		DEBUG=1
		shift 1
		;;
	'') break ;;
	*)
		SVCS="$([ -n "${SVCS}" ] && echo "${SVCS}, " || echo "")\"${1}\""
		shift 1
		;;
	esac
done

if [ -z "${ENDPOINT_ADDRESS}" ]; then
	echo "Missing --endpoint-address ENDPOINT_ADDRESS"
	exit 3
fi

if [ -z "${SVCS}" ]; then
	echo "Need at least one service"
	exit 3
fi

if [ ! -f "${DESCRIPTOR}" ]; then
	echo "${0}: cannot stat '${DESCRIPTOR}': No such file"
	exit 3
fi

BUILD_DIR="tmp/build-$(date +%s)"
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
            name: proxy_route
            virtual_hosts:
            - name: proxy_target
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  host_rewrite_literal: PLACEHOLDER_ENDPOINT_ADDRESS
                  cluster: proxy_target
                  timeout: 90s
              cors:
                allow_origin_string_match:
                  - safe_regex: {google_re2: {}, regex: \*}
                allow_methods: "OPTIONS GET POST PUT DELETE PATCH"
                allow_headers: "*"
                expose_headers: grpc-status grpc-message
                allow_credentials: true
          http_filters:
          - name: envoy.filters.http.grpc_json_transcoder
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_json_transcoder.v3.GrpcJsonTranscoder
              proto_descriptor: "/configs/descriptor.pb"
              services: [ ${SVCS} ]
          - name: envoy.filters.http.cors
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          access_log:
            - name: envoy.access_loggers.stdout
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog

  clusters:
  - name: proxy_target
    type: LOGICAL_DNS
    dns_lookup_family: V4_ONLY
    typed_extension_protocol_options:
      envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
        "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
        explicit_http_config:
          http2_protocol_options: {}
    load_assignment:
      cluster_name: proxy_target
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: PLACEHOLDER_ENDPOINT_ADDRESS
                port_value: 443
    transport_socket:
      name: envoy.transport_sockets.tls
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
        sni: PLACEHOLDER_ENDPOINT_ADDRESS
EOF

cat >"${BUILD_DIR}/entrypoint.sh" <<EOF
#!/usr/bin/env bash

YAML=\$(
	sed -E "s/PLACEHOLDER_LISTENER_PORT/\${LISTENER_PORT}/g" /configs/config.yaml | \
		sed -E "s/PLACEHOLDER_ENDPOINT_ADDRESS/\${ENDPOINT_ADDRESS}/g"
)

echo "Proxying: \${LISTENER_PORT} --> \${ENDPOINT_ADDRESS}"

envoy --config-yaml "\${YAML}"

EOF
chmod +x "${BUILD_DIR}/entrypoint.sh"

################################################################################

cat >"${BUILD_DIR}/Dockerfile" <<EOF
FROM envoyproxy/envoy:v1.21-latest

COPY config.yaml /configs/
COPY entrypoint.sh /

ENV LISTENER_PORT="${LISTENER_PORT}"
ENV ENDPOINT_ADDRESS="${ENDPOINT_ADDRESS}"

COPY descriptor.pb /configs/

CMD /entrypoint.sh
EOF

(
	cd ${BUILD_DIR}
	docker build \
		-t ${IMAGE_NAME} .
)

[ -z "${DEBUG}" ] && rm -rf "${BUILD_DIR}" || echo "Build artefacts remain in: ${BUILD_DIR}"
