# Copyright 2016 The Prometheus Authors
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Needs to be defined before including Makefile.common to auto-generate targets
DOCKER_ARCHS ?= amd64 armv7 arm64

include Makefile.common

DOCKER_IMAGE_NAME ?= pushgateway

GOHOSTOS=linux
PROMU_BINARIES=pushgateway
imageName=kekek/pushgateway
tagVersion=v3
images=$(imageName):$(tagVersion)

assets:
	@echo ">> writing assets"
	@cd $(PREFIX)/asset && GO111MODULE=$(GO111MODULE) $(GO) generate && $(GOFMT) -w assets_vfsdata.go

.PHONY: build
build:
	@echo ">> building binaries"
	GOOS=linux GO111MODULE=$(GO111MODULE) $(PROMU) build --prefix $(PREFIX) $(PROMU_BINARIES)

.PHONY: docker
docker:
	@echo ">> build docker images: $(images)"
	docker build -t $(images) -f $(DOCKERFILE_PATH) ./

.PHONY: push
push:
	@echo ">> push docker images ${images}"
	docker push $(images)
