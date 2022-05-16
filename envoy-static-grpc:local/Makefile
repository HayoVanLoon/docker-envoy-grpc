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

IMAGE_NAME := envoy-static-grpc:local

LISTENER_PORT := 10000
ENDPOINT_PORT := 8081

CMD :=


build:
ifndef SERVICES
	$(error Missing SERVICES)
endif
	./build.sh \
		--lp $(LISTENER_PORT) \
		--ep $(ENDPOINT_PORT) \
		$(SERVICES)

run:
	docker run \
		--network host \
		-i -t \
		$(IMAGE_NAME) \
		$(CMD)
