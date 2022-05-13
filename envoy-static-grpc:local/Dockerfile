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

FROM envoyproxy/envoy:v1.21-latest

ARG DESCRIPTOR=descriptor.pb
ARG TEMPLATE_CONFIG=local-grpc-template.yaml

ARG LISTENER_PORT
# List of quoted service names, separated by comma's, i.e.: "foo", "bar"
ARG SERVICES
ARG ENDPOINT_PORT

WORKDIR /configs

COPY ${DESCRIPTOR} descriptor.pb

COPY ${TEMPLATE_CONFIG} config.yaml
RUN sed -i -E "s/PLACEHOLDER_LISTENER_PORT/${LISTENER_PORT}/g" config.yaml
RUN sed -i -E "s/PLACEHOLDER_SERVICES/${SERVICES}/g" config.yaml
RUN sed -i -E "s/PLACEHOLDER_ENDPOINT_PORT/${ENDPOINT_PORT}/g" config.yaml

CMD envoy -c "/configs/config.yaml"
