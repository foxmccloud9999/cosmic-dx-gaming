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
build-qcow2 image="ghcr.io/foxmccloud9999/cosmic-dx-gaming:latest":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p output
    if ! sudo podman image exists "{{image}}"; then
        echo "Image '{{image}}' not found in root Podman storage; pulling..."
        sudo podman pull "{{image}}"
    fi
    sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v "$(pwd)/output:/output" \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        --local \
        "{{image}}"

# Remove local VM build output
clean:
    rm -rf output
