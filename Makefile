# ShapeBit OS image. Run `make help` to list targets.
# Every variable below can be overridden, e.g. `make test ENGINE=docker`.

# Installing to a disk needs a root-capable engine: rootful Podman or Docker.
ENGINE         ?= sudo podman
IMAGE          ?= localhost/shapebit-os:dev
FEDORA_VERSION ?= 44
IMAGE_VERSION  ?= dev
BUILD          ?= build
DISK           ?= $(BUILD)/disk.raw
IMAGE_SIZE     ?= 12G
DISK_SIZE      ?= 20G
SSH_PORT       ?= 2222
SSH_KEY        ?= $(BUILD)/ssh/id_ed25519
# The VM's first owner, an administrator created on first boot.
OWNER_NAME     ?= dev
OWNER_PASSWORD ?= $(BUILD)/owner-password
RECOVERY_KEY   ?= $(BUILD)/recovery-key
KEYS_DIR       ?= $(BUILD)/keys
BOOT_TIMEOUT   ?= 300
# Local registry that serves updates; the VM reaches the host at 10.0.2.2
# (QEMU user networking), so installed systems update from UPDATE_REF.
REGISTRY_PORT  ?= 5000
UPDATE_REF     ?= 10.0.2.2:$(REGISTRY_PORT)/shapebit-os:dev

export ENGINE IMAGE FEDORA_VERSION IMAGE_VERSION BUILD DISK IMAGE_SIZE DISK_SIZE SSH_PORT SSH_KEY OWNER_NAME OWNER_PASSWORD RECOVERY_KEY KEYS_DIR BOOT_TIMEOUT REGISTRY_PORT UPDATE_REF

.DEFAULT_GOAL := help
.PHONY: help image check publish disk vm ssh test test-update clean

help: ## List targets
	@awk -F ':.*## ' '/^[a-z-]+:.*## / { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

KEYS := $(foreach name,PK KEK db,$(KEYS_DIR)/$(name).key $(KEYS_DIR)/$(name).crt) \
        $(KEYS_DIR)/tpm2-pcr-private.pem $(KEYS_DIR)/tpm2-pcr-public.pem

image: $(KEYS) ## Build the container image with its signed UKI
	scripts/image.sh

check: image ## Run checks inside the container image
	$(ENGINE) run --rm -i --network none $(IMAGE) bash -s < tests/image.sh

publish: image ## Push the image to the local update registry
	scripts/publish.sh

disk: image ## Install the image to an encrypted raw disk
	scripts/disk.sh

vm: $(SSH_KEY) $(OWNER_PASSWORD) ## Boot the disk in QEMU on this terminal (Ctrl-A X quits)
	scripts/vm.sh

ssh: $(SSH_KEY) ## Open a root shell in the running VM
	scripts/ssh.sh

test: check disk $(SSH_KEY) $(OWNER_PASSWORD) ## Boot the disk and run checks inside the system
	tests/boot.sh

test-update: disk $(SSH_KEY) $(OWNER_PASSWORD) ## Update an installed system to a new build, then roll back
	tests/update.sh

clean: ## Remove build outputs
	rm -rf $(BUILD)

$(SSH_KEY):
	mkdir -p $(@D)
	ssh-keygen -q -t ed25519 -N '' -C shapebit-dev -f $@

# Development-only password of the VM's first owner.
$(OWNER_PASSWORD):
	mkdir -p $(@D)
	head -c 18 /dev/urandom | base64 | tr -d '\n' > $@

# Development-only signing keys.
$(KEYS) &:
	scripts/keys.sh
