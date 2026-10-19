# Boîte à outils de la chaîne CI/CD : les mêmes outils et versions que le pipeline,
# dans une image. Permet de lancer tous les contrôles n'importe où avec Docker.
#
#   docker build -t kalipay-ci -f ci/Dockerfile .
#   docker run --rm -v "$PWD:/repo" kalipay-ci
FROM python:3.13-slim-trixie

ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG TRIVY_VERSION=0.75.0
ARG TRIVY_SHA256=c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f
ARG CONFTEST_VERSION=0.71.0
ARG CONFTEST_SHA256=765dfefdf0730693d7541ea0147e10d530a54ed257bbfec055ff34c837ffdf72
ARG KYVERNO_VERSION=1.19.1
ARG KYVERNO_SHA256=b38228f367fc0fdc2b08f4c83ea50ac5f16c60ff8d62d76a66157c33c47b70ae

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

# Chaque binaire est vérifié par son empreinte SHA-256 avant d'être installé
RUN set -eux; cd /tmp; \
    dl() { curl -sSfLo "$1" "$2"; echo "$3  $1" | sha256sum -c -; tar xzf "$1" -C /usr/local/bin "$4"; rm "$1"; }; \
    dl gl.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "$GITLEAKS_SHA256" gitleaks; \
    dl tv.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "$TRIVY_SHA256" trivy; \
    dl ct.tgz "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" "$CONFTEST_SHA256" conftest; \
    dl ky.tgz "https://github.com/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz" "$KYVERNO_SHA256" kyverno

RUN pip install --no-cache-dir checkov==3.3.22 semgrep==1.179.0

# Base de vulnérabilités Trivy préchargée : les scans marchent aussi hors ligne
ENV TRIVY_CACHE_DIR=/opt/trivy-cache
RUN trivy fs --download-db-only -q . && chmod -R a+rX /opt/trivy-cache

RUN useradd -m -u 1000 ci && git config --system --add safe.directory /repo
USER ci
ENV SEMGREP_SEND_METRICS=off TRIVY_SKIP_DB_UPDATE=true HOME=/home/ci
WORKDIR /repo
ENTRYPOINT ["./demo/verifier-local.sh"]
