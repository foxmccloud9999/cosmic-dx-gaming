image_name := "cosmic-dx-gaming"
fedora_version := "45"

# Show available local developer recipes
default:
    @just --list

# Replace YOUR_GITHUB_USERNAME (and optionally image name) across repo configs
configure github_user new_image_name=image_name:
    #!/usr/bin/env bash
    set -euo pipefail
    OWNER_LOWER="{{github_user}}"
    OWNER_LOWER="${OWNER_LOWER,,}"
    NAME_LOWER="{{new_image_name}}"
    NAME_LOWER="${NAME_LOWER,,}"
    OLD_NAME="{{image_name}}"

    sed -i "s|YOUR_GITHUB_USERNAME|${OWNER_LOWER}|g" \
        Containerfile \
        "system_files/etc/containers/registries.d/${OLD_NAME}.yaml" \
        README.md

    if [[ "$NAME_LOWER" != "$OLD_NAME" ]]; then
        sed -i "s|${OLD_NAME}|${NAME_LOWER}|g" \
            Containerfile \
            .github/workflows/build.yml \
            README.md \
            "system_files/etc/containers/registries.d/${OLD_NAME}.yaml"
        sed -i "s|^image_name := \".*\"|image_name := \"${NAME_LOWER}\"|" Justfile
        mv "system_files/etc/containers/registries.d/${OLD_NAME}.yaml" \
           "system_files/etc/containers/registries.d/${NAME_LOWER}.yaml"
    fi

    echo "Configured repository for ghcr.io/${OWNER_LOWER}/${NAME_LOWER}"

# Generate Cosign keypair (cosign.pub is committed; cosign.key stays gitignored & goes in GitHub Secrets)
generate-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f cosign.key || -f cosign.pub ]]; then
        echo "cosign.key or cosign.pub already exists. Remove them first if you intend to rotate keys." >&2
        exit 1
    fi
    if command -v cosign >/dev/null 2>&1; then
        COSIGN_PASSWORD="" cosign generate-key-pair
    elif command -v podman >/dev/null 2>&1; then
        podman run --rm --user 0 --security-opt label=disable \
            -v "$(pwd):/work" \
            -w /work \
            -e COSIGN_PASSWORD="" \
            ghcr.io/sigstore/cosign/cosign:v2.4.1 \
            generate-key-pair
    else
        echo "ERROR: Neither cosign nor podman is installed locally." >&2
        exit 1
    fi
    echo ""
    echo "Keys generated:"
    echo "  - cosign.pub -> commit this to your repository."
    echo "  - cosign.key -> gitignored! Paste its entire contents into GitHub Repo Settings -> Secrets -> Actions -> COSIGN_PRIVATE_KEY"

# Build the bootc container image locally with Podman
build owner="foxmccloud9999":
    podman build \
        --build-arg FEDORA_VERSION={{fedora_version}} \
        --build-arg IMAGE_NAME={{image_name}} \
        --build-arg IMAGE_OWNER={{owner}} \
        -t localhost/{{image_name}}:latest \
        .

# Run bootc structural lint and smoke checks against the local build
lint:
    podman run --rm localhost/{{image_name}}:latest bash -euo pipefail -c ' \
        bootc container lint && \
        just --justfile /usr/share/ublue-os/just/60-custom.just --list && \
        command -v ujust docker podman distrobox gamescope mangohud gamemoderun steam \
    '

# Build a bootable QCOW2 VM disk image in ./output/qcow2/disk.qcow2 using bootc-image-builder
# Note: bootc-image-builder reads root's container storage (/var/lib/containers/storage).
# Pulls from GHCR into root storage if not already present locally as root.
build-qcow2 image="ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest" config="output/vm-config.toml":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    if ! sudo podman image exists "{{image}}"; then
        echo "Image '{{image}}' not found in root Podman storage; pulling..."
        sudo podman pull "{{image}}"
    fi
    CONFIG_PATH="{{config}}"
    BIB_VOL_ARGS=()
    BIB_CFG_ARGS=()
    if [[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]]; then
        BIB_VOL_ARGS+=(-v "$(realpath "$CONFIG_PATH"):/config.toml:ro")
        BIB_CFG_ARGS+=(--config /config.toml)
    fi
    sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v "$(pwd)/output:/output" \
        "${BIB_VOL_ARGS[@]}" \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        --rootfs ext4 \
        "${BIB_CFG_ARGS[@]}" \
        --local \
        "{{image}}"
    sudo chown -R "$(id -u):$(id -g)" output/qcow2

# Boot ./output/qcow2/disk.qcow2 in QEMU/KVM with UEFI (pass gl=off to fall back to software rendering)
run-vm gl="on":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f output/qcow2/disk.qcow2 ]]; then
        echo "ERROR: output/qcow2/disk.qcow2 not found. Run 'just build-qcow2' first." >&2
        exit 1
    fi
    if [[ ! -f output/OVMF_VARS.fd ]]; then
        cp /usr/share/edk2/ovmf/OVMF_VARS.fd output/OVMF_VARS.fd
    fi
    if [[ "{{gl}}" == "on" ]]; then
        GFX_ARGS=(-device virtio-vga-gl -display gtk,gl=on)
    else
        GFX_ARGS=(-device virtio-vga -display gtk)
    fi
    exec qemu-system-x86_64 \
        -enable-kvm \
        -machine q35 \
        -cpu host \
        -smp 6 \
        -m 8192 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file=output/OVMF_VARS.fd \
        -drive file=output/qcow2/disk.qcow2,format=qcow2,if=virtio \
        "${GFX_ARGS[@]}" \
        -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
        -device intel-hda \
        -device hda-duplex

# Remove local VM build output
clean:
    rm -rf output
