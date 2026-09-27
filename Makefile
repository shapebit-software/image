# ShapeBit OS image. Run `make help` to list targets.
# Every variable below can be overridden, e.g. `make test ENGINE=docker`.

# Installing to a disk needs a root-capable engine: rootful Podman or Docker.
ENGINE         ?= sudo podman
IMAGE          ?= localhost/shapebit-os:dev
FEDORA_VERSION ?= 44
BUILD          ?= build
DISK           ?= $(BUILD)/disk.raw
DISK_SIZE      ?= 20G
SSH_PORT       ?= 2222
SSH_KEY        ?= $(BUILD)/ssh/id_ed25519
LUKS_KEY       ?= $(BUILD)/luks/passphrase

export ENGINE IMAGE BUILD DISK DISK_SIZE SSH_PORT SSH_KEY LUKS_KEY

.DEFAULT_GOAL := help
.PHONY: help image check disk vm ssh test clean

help: ## List targets
	@awk -F ':.*## ' '/^[a-z]+:.*## / { printf "  %-6s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

image: ## Build the container image
	$(ENGINE) build --build-arg FEDORA_VERSION=$(FEDORA_VERSION) -f Containerfile -t $(IMAGE) .

check: image ## Run checks inside the container image
	$(ENGINE) run --rm -i --network none $(IMAGE) bash -s < tests/image.sh

disk: image $(LUKS_KEY) ## Install the image to an encrypted bootable raw disk
	scripts/disk.sh

vm: $(SSH_KEY) $(LUKS_KEY) ## Boot the disk in QEMU on this terminal (Ctrl-A X quits)
	scripts/vm.sh

ssh: $(SSH_KEY) ## Open a root shell in the running VM
	scripts/ssh.sh

test: check disk $(SSH_KEY) $(LUKS_KEY) ## Boot the disk and run checks inside the system
	tests/boot.sh

clean: ## Remove build outputs
	rm -rf $(BUILD)

$(SSH_KEY):
	mkdir -p $(@D)
	ssh-keygen -q -t ed25519 -N '' -C shapebit-dev -f $@

# Development-only disk passphrase, without a trailing newline.
$(LUKS_KEY):
	mkdir -p $(@D)
	head -c 32 /dev/urandom | base64 | tr -d '\n' > $@
