# Envoy with gRPC configurations

Build scripts for various grpc-json transcoding Envoy proxies.

## Tags / Flavours

There are various tags / flavours for different situations.Each tag has its
directory.

Use the `build.sh` script in there to build the image. Its parameters are
explained in its help function accessible via `build.sh --help`.

|tag|description|
|---|---|
| local| local proxy|
|simple-tls| proxy to host over TLS|
|simple-jwt| proxy to host over TLS with token validation [work in progress]|

# License

Copyright 2022 Hayo van Loon

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

       http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
