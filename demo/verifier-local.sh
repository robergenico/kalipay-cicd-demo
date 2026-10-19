#!/usr/bin/env bash
# Lance en local les contrôles du pipeline qui ne demandent pas Docker.
# Prérequis dans le PATH : gitleaks, semgrep, trivy, checkov, conftest, kyverno.
set -uo pipefail
cd "$(dirname "$0")/.."
echec=0
etape() {
  local nom="$1"; shift
  if "$@" >/tmp/kalipay-etape.log 2>&1; then
    printf '  \033[32mOK\033[0m     %s\n' "$nom"
  else
    printf '  \033[31mBLOQUÉ\033[0m %s\n' "$nom"; sed 's/^/           /' /tmp/kalipay-etape.log | grep -vE '^\s*$' | tail -8
    echec=1
  fi
}
etape "Secrets (gitleaks)"        gitleaks dir --redact --no-banner --config .gitleaks.toml .
etape "Code (Semgrep)"            semgrep scan --config .semgrep/ --error --metrics=off --quiet app/
etape "Dépendances (Trivy)"       trivy fs -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 app/
etape "Infra en code (Checkov)"   checkov --config-file .checkov.yaml
etape "Matrice de flux (Conftest)" conftest test k8s/ --no-color --policy policies/flow-matrix --data policies/flow-matrix/flow-matrix.yaml
etape "Admission (Kyverno)"       kyverno apply policies/kyverno/disallow-root.yaml policies/kyverno/require-limits.yaml --resource k8s/deployment.yaml
exit $echec
