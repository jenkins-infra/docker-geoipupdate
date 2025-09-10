ARG GEOIPUPDATE_VERSION=v7.1.1
ARG AZCOPY_VERSION=10.30.1
ARG AZ_VERSION=2.77.0
ARG KUBECTL_VERSION=1.26.12

FROM ubuntu:22.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends jq wget ca-certificates gnupg lsb-release\
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG user=azcopy
ARG group=azcopy
ARG uid=1000
ARG gid=1000
ARG user_home="/home/${user}"
RUN groupadd -g ${gid} ${group} \
    && useradd -l -d "${user_home}" -u "${uid}" -g "${gid}" -m -s /bin/bash "${user}"

ARG AZCOPY_VERSION=10.30.1
RUN rep_config_pkg="$(mktemp)" \
    # Download and install the repository configuration package.
    && wget -qO- "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O "${rep_config_pkg}" \
    && dpkg --install "${rep_config_pkg}" \
    && rm -f "${rep_config_pkg}" \
    && apt-get update --quiet \
    && apt-get install --yes --no-install-recommends azcopy="${AZCOPY_VERSION}" \
    # Sanity check
    && azcopy --version \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG AZ_VERSION=2.77.0
RUN mkdir -p /etc/apt/keyrings && \
    wget --quiet --output-document - "https://packages.microsoft.com/keys/microsoft.asc" | gpg --dearmor | tee /etc/apt/keyrings/microsoft.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/microsoft.gpg && \
    AZ_DIST="$(lsb_release -cs)" && \
    printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-by: /etc/apt/keyrings/microsoft.gpg' "${AZ_DIST}" "$(dpkg --print-architecture)" | tee /etc/apt/sources.list.d/azure-cli.sources && \
    apt-get update && apt-get install -y --no-install-recommends azure-cli="${AZ_VERSION}-1~${AZ_DIST}" && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG GEOIPUPDATE_VERSION=v7.1.1
RUN ARCH="$(uname -m)" && \
    if [ "$ARCH" = "x86_64" ]; then \
        DOWNLOAD_URL="https://github.com/maxmind/geoipupdate/releases/download/${GEOIPUPDATE_VERSION}/geoipupdate_${GEOIPUPDATE_VERSION#v}_linux_amd64.tar.gz"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        DOWNLOAD_URL="https://github.com/maxmind/geoipupdate/releases/download/${GEOIPUPDATE_VERSION}/geoipupdate_${GEOIPUPDATE_VERSION#v}_linux_arm64.tar.gz"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
&& wget -qO- "${DOWNLOAD_URL}" -O /tmp/geoipupdate.tgz \
&& BIN_LOCATION=$(tar -tzf /tmp/geoipupdate.tgz | grep "/geoipupdate$") \
&& export BIN_LOCATION \
&& tar -xvzf /tmp/geoipupdate.tgz --strip-components=1 --directory=/usr/bin/ "$BIN_LOCATION" \
&& chmod +x /usr/bin/geoipupdate

ARG KUBECTL_VERSION
RUN ARCH="$(uname -m)" && \
    if [ "$ARCH" = "x86_64" ]; then \
        DOWNLOAD_URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    elif [ "$ARCH" = "aarch64" ]; then \
    DOWNLOAD_URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/arm64/kubectl"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
    && wget "${DOWNLOAD_URL}" --quiet --output-document=/usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && kubectl version --client --output=yaml 2>&1 | grep -q "${KUBECTL_VERSION}"

USER "${user}"

COPY get-fileshare-signed-url.sh /usr/bin/get-fileshare-signed-url.sh
COPY entrypoint.sh /usr/bin/entrypoint.sh
ENTRYPOINT ["/usr/bin/entrypoint.sh"]
