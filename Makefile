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
RECOVERY_KEY   ?= $(BUILD)/recovery-key
KEYS_DIR       ?= $(BUILD)/keys
BOOT_TIMEOUT   ?= 300

export ENGINE IMAGE FEDORA_VERSION BUILD DISK DISK_SIZE SSH_PORT SSH_KEY RECOVERY_KEY KEYS_DIR BOOT_TIMEOUT

.DEFAULT_GOAL := help
.PHONY: help image check disk vm ssh test clean

help: ## List targets
	@awk -F ':.*## ' '/^[a-z]+:.*## / { printf "  %-6s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

KEYS := $(foreach name,PK KEK db,$(KEYS_DIR)/$(name).key $(KEYS_DIR)/$(name).crt) \
        $(KEYS_DIR)/tpm2-pcr-private.pem $(KEYS_DIR)/tpm2-pcr-public.pem

image: $(KEYS) ## Build the container image with its signed UKI
	scripts/image.sh

check: image ## Run checks inside the container image
	$(ENGINE) run --rm -i --network none $(IMAGE) bash -s < tests/image.sh

disk: image $(SSH_KEY) ## Install the image to an encrypted disk and enroll the VM's TPM2
	scripts/disk.sh
	scripts/enroll.sh

vm: $(SSH_KEY) ## Boot the disk in QEMU on this terminal (Ctrl-A X quits)
	scripts/vm.sh

ssh: $(SSH_KEY) ## Open a root shell in the running VM
	scripts/ssh.sh

test: check disk ## Boot the disk and run checks inside the system
	tests/boot.sh

clean: ## Remove build outputs
	rm -rf $(BUILD)

$(SSH_KEY):
	mkdir -p $(@D)
	ssh-keygen -q -t ed25519 -N '' -C shapebit-dev -f $@

# Development-only signing keys.
$(KEYS) &:
	scripts/keys.sh
