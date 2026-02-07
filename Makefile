UID ?= $(shell id -u)
GID ?= $(shell id -g)
COMPOSE ?= docker compose
COMPOSE_PROJECT_NAME ?= trivalent

export UID GID COMPOSE_PROJECT_NAME

.PHONY: image build shell deps clean

image:
	$(COMPOSE) build

build:
	mkdir -p out/debian .cache
	# Best-effort permissions so rootless containers can write to bind mounts.
	# Some cached artifacts may be owned by other users; ignore chmod failures.
	chmod -R a+rwX .cache out || true
	$(COMPOSE) run --rm trivalent-build ./debian_build.sh

shell:
	$(COMPOSE) run --rm trivalent-build bash

# Optional: prefetch and install dependencies by rebuilding the image
# (the Dockerfile already installs build deps).
deps: image
	@echo "Dependencies are installed as part of the image build."

clean:
	$(COMPOSE) down --remove-orphans --volumes
	-docker image rm -f $(COMPOSE_PROJECT_NAME)-trivalent-build >/dev/null 2>&1 || true
	rm -rf out/debian .cache
