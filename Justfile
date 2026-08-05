set shell := ["bash", "-cu"]

image_tag := env_var_or_default("SHAPEBIT_OS_IMAGE", "localhost/shapebit-os:dev")
disk_path := env_var_or_default("SHAPEBIT_OS_DISK", "build/shapebit-os.qcow2")

build:
    ./scripts/build-image.sh "{{image_tag}}"

lint:
    ./scripts/lint-image.sh "{{image_tag}}"

inspect:
    podman run --rm -it "{{image_tag}}" /usr/lib/shapebit-os/shapebit-os-info

disk:
    ./scripts/build-disk.sh "{{image_tag}}" "{{disk_path}}"

run:
    ./scripts/run-qemu.sh "{{disk_path}}"

test:
    ./tests/test-container.sh "{{image_tag}}"
