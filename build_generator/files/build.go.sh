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

SCRIPT_ID="{{.Tag}}"

SVCS=
{{range .Parameters}}{{if .Variable}}
{{.Variable}}={{if .DefaultValue}}"{{.DefaultValue}}"{{end}}{{end}}{{end}}

usage() {
	B=$(tput bold)
	X=$(tput sgr0)
	echo -e "
${B}NAME${X}
    ${0} - build an image for a gRPC-json proxy to a local service

${B}SYNOPSIS${X}
    ${0}{{range .Parameters}}{{if .Required}} {{index .Names 0}}{{if.Parameter}} {{.Parameter}}{{end}}{{end}}{{end}}{{range .Parameters}}{{if not .Required}} [{{index .Names 0}}{{if.Parameter}} {{.Parameter}}{{end}}]{{end}}{{end}} SERVICE_NAME [SERVICE_NAME...]

${B}DESCRIPTION${X}
    Builds an image with a static gRPC config.
{{range .SortedParams}}
	${B}{{.NamesFormatted}}${X}{{if.Parameter}} {{.Parameter}}{{end}}
        {{.Description}}{{if .Required}} Required.{{else if .Parameter}} Defaults to '${ {{- .Variable -}} }'.{{end}}
{{end}}"
}

while true; do
	case ${1} in
{{range .Parameters}}	{{.NamesFormatted}})
		{{if .Parameter}}{{.Variable}}=${2}
		shift 2{{else}}{{.Variable}}={{.FixedValue}}
		shift 1{{end}}
		;;
{{end}}	--help)
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
{{range .Parameters}}{{if .Required}}if [ -z "${ {{- .Variable -}} }" ]; then
	echo "Missing {{index .Names 0}} {{.Variable}}"
	exit 3
fi{{end}}{{end}}
if [ ! -f "${DESCRIPTOR}" ]; then
	echo "${0}: cannot stat '${DESCRIPTOR}': No such file"
	exit 3
fi

echo "{{range .Parameters}}
{{.Variable}}: \"${ {{- .Variable -}} }\"{{end}}
"

BUILD_DIR="tmp/build-${SCRIPT_ID}-$(date +%s)"
mkdir -p "${BUILD_DIR}"

cp "${DESCRIPTOR}" "${BUILD_DIR}"

cat >"${BUILD_DIR}/config.yaml" <<EOF
{{.YamlData}}
EOF

cat >"${BUILD_DIR}/entrypoint.sh" <<EOF
#!/usr/bin/env bash

set -eo pipefail

YAML=\$(
	cat /configs/config.yaml{{range .Parameters}}{{if .Runtime}} | \
		sed "s/PLACEHOLDER_{{.Variable}}/\${ {{- .Variable -}} }/g"{{end}}{{end}}
)

if [ -n "\${ENVOY_VALIDATE}" ]; then
	envoy --mode validate --config-yaml "\${YAML}"
	exit 0
fi
{{range .Parameters}}{{if .Runtime}}
echo {{.Variable}}: "\${ {{- .Variable -}} }"{{end}}{{end}}

envoy --config-yaml "\${YAML}"

EOF
chmod +x "${BUILD_DIR}/entrypoint.sh"

################################################################################

cat >"${BUILD_DIR}/Dockerfile" <<EOF
FROM envoyproxy/envoy:v1.21-latest

COPY config.yaml /configs/
COPY entrypoint.sh /

ENV ENVOY_VALIDATE=""{{range .Parameters}}{{if .Runtime}}
ENV {{.Variable}}="${ {{- .Variable -}} }"{{end}}{{end}}

COPY descriptor.pb /configs/

CMD /entrypoint.sh
EOF

(
	cd ${BUILD_DIR}
	docker build \
		-t ${IMAGE_NAME} .
)

[ -z "${DEBUG}" ] && rm -rf "${BUILD_DIR}" || echo "Build artefacts remain in: ${BUILD_DIR}"

docker run \
	--env ENVOY_VALIDATE=1 \
	-i -t ${IMAGE_NAME}
