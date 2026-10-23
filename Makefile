# ShapeBit OS image. Run `make help` to list targets.
# Every variable below can be overridden, e.g. `make test ENGINE=docker`.

# Installing to a disk needs a root-capable engine: rootful Podman or Docker.
ENGINE         ?= sudo podman
IMAGE          ?= localhost/shapebit-os:dev
FEDORA_VERSION ?= 44
IMAGE_VERSION  ?= dev
BUILD          ?= build
DISK           ?= $(BUILD)/disk.raw
DISK_SIZE      ?= 20G
# The installer medium: its image, its source tree, and its raw disk.
INSTALLER_IMAGE ?= localhost/shapebit-os-installer:dev
INSTALLER_SRC   ?= ../installer
# The desktop's source tree, which the image installs.
DESKTOP_SRC     ?= ../desktop
MEDIUM          ?= $(BUILD)/installer.raw
MEDIUM_SIZE     ?= 10G
SSH_PORT       ?= 2222
SSH_KEY        ?= $(BUILD)/ssh/id_ed25519
# The first owner, an administrator that the installer creates.
OWNER_NAME     ?= dev
OWNER_PASSWORD ?= $(BUILD)/owner-password
RECOVERY_KEY   ?= $(BUILD)/recovery-key
# Settings of the installed system, as chosen in the installer. They differ
# from the image's defaults, so the tests show that the installer applied them.
LOCALE          ?= en_GB.UTF-8
KEYBOARD_LAYOUT ?= pl
TIME_ZONE       ?= Europe/Warsaw
KEYS_DIR       ?= $(BUILD)/keys
BOOT_TIMEOUT   ?= 300
# Local registry that serves updates; the VM reaches the host at 10.0.2.2
# (QEMU user networking), so installed systems update from UPDATE_REF.
REGISTRY_PORT  ?= 5000
UPDATE_REF     ?= 10.0.2.2:$(REGISTRY_PORT)/shapebit-os:dev

export ENGINE IMAGE FEDORA_VERSION IMAGE_VERSION BUILD DISK DISK_SIZE INSTALLER_IMAGE MEDIUM MEDIUM_SIZE SSH_PORT SSH_KEY OWNER_NAME OWNER_PASSWORD RECOVERY_KEY LOCALE KEYBOARD_LAYOUT TIME_ZONE KEYS_DIR BOOT_TIMEOUT REGISTRY_PORT UPDATE_REF

.DEFAULT_GOAL := help
.PHONY: help image check publish installer disk vm installer-vm ssh test test-update clean

help: ## List targets
	@awk -F ':.*## ' '/^[a-z-]+:.*## / { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

KEYS := $(foreach name,PK KEK db,$(KEYS_DIR)/$(name).key $(KEYS_DIR)/$(name).crt) \
        $(KEYS_DIR)/tpm2-pcr-private.pem $(KEYS_DIR)/tpm2-pcr-public.pem

image: $(KEYS) ## Build the container image with its signed UKI
	scripts/image.sh Containerfile $(IMAGE) $(BUILD)/image.tar \
	  --build-arg FEDORA_VERSION=$(FEDORA_VERSION) --build-arg IMAGE_VERSION=$(IMAGE_VERSION) \
	  --build-context desktop=$(DESKTOP_SRC)

check: image ## Run checks inside the container image
	$(ENGINE) run --rm -i --network none $(IMAGE) bash -s < tests/image.sh

publish: image ## Push the image to the local update registry
	scripts/publish.sh

installer: image ## Build the installer medium, which carries the image
	scripts/image.sh Containerfile.installer $(INSTALLER_IMAGE) $(BUILD)/installer.tar \
	  --build-arg BASE=$(IMAGE)-unsealed --build-arg UPDATE_REF=$(UPDATE_REF) \
	  --build-context installer=$(INSTALLER_SRC) --build-context payload=$(BUILD)
	scripts/medium.sh

disk: installer $(SSH_KEY) $(OWNER_PASSWORD) ## Install to a new disk: boot the medium in QEMU and run the installer
	scripts/disk.sh

vm: $(SSH_KEY) ## Boot the installed disk in QEMU on this terminal (Ctrl-A X quits)
	scripts/vm.sh

installer-vm: installer $(SSH_KEY) ## Boot the medium with a new disk in a window, to install by hand
	scripts/disk.sh --window

ssh: $(SSH_KEY) ## Open a root shell in the running VM
	scripts/ssh.sh

test: check disk ## Install, boot the installed disk, and run checks inside the system
	tests/boot.sh

test-update: disk ## Update an installed system to a new build, then roll back
	tests/update.sh

clean: ## Remove build outputs
	rm -rf $(BUILD)

$(SSH_KEY):
	mkdir -p $(@D)
	ssh-keygen -q -t ed25519 -N '' -C shapebit-dev -f $@

# Development-only password of the first owner.
$(OWNER_PASSWORD):
	mkdir -p $(@D)
	head -c 18 /dev/urandom | base64 | tr -d '\n' > $@

# Development-only signing keys.
$(KEYS) &:
	scripts/keys.sh
