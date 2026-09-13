#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
KEY="${KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
REMOTE="${REMOTE:-git@github.com:MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App.git}"
VERSION="${VERSION:-1.0.0}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="/root/studiosat-git-backups/$TS"
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
[[ -f "$KEY" ]] || fail "chave GitHub ausente: $KEY"
[[ -d "$REPO/.git" ]] || fail "repositorio ausente: $REPO"
cd "$REPO"

printf '\n===== A. NORMALIZANDO GIT =====\n'
# Evita que chmod em scripts de shell seja interpretado como alteracao de conteudo.
git config core.fileMode false
git config core.sshCommand "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

DIRTY="$(git status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  mkdir -p "$BACKUP_DIR"
  git status --short > "$BACKUP_DIR/status.txt"
  git diff > "$BACKUP_DIR/worktree.patch" || true
  git diff --cached > "$BACKUP_DIR/index.patch" || true
  echo "Alteracoes locais reais encontradas; salvando em stash antes de sincronizar:"
  cat "$BACKUP_DIR/status.txt"
  git stash push -u -m "studiosat-auto-backup-$TS" >/tmp/studiosat-stash.txt
  cat /tmp/studiosat-stash.txt
  git stash list -1 > "$BACKUP_DIR/stash.txt"
  echo "LOCAL_BACKUP=$BACKUP_DIR"
fi
ok "Git normalizado"

printf '\n===== B. GITHUB =====\n'
SSH_OUT="$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com 2>&1 || true)"
printf '%s\n' "$SSH_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_OUT" || fail "GitHub SSH nao autenticou"
ok "GitHub SSH"

printf '\n===== C. SINCRONIZACAO =====\n'
git fetch origin main
git checkout main
git pull --ff-only origin main
ok "main sincronizada: $(git rev-parse --short HEAD)"

printf '\n===== D. VALIDACAO DOS SCRIPTS =====\n'
for f in scripts/deploy-universal-platforms.sh scripts/fix-universal-routing.sh scripts/fix-hls-cors.sh scripts/deploy-download-page.sh; do
  [[ -f "$f" ]] || fail "arquivo ausente: $f"
  bash -n "$f"
done
python3 -m py_compile scripts/generate-pwa-icons.py
ok "scripts validos"

printf '\n===== E. DEPLOY UNIVERSAL =====\n'
VERSION="$VERSION" bash scripts/deploy-universal-platforms.sh
ok "deploy universal concluido"

printf '\n========================================\n'
printf 'SYNC_AND_DEPLOY=PASS\n'
printf 'HEAD=%s\n' "$(git rev-parse HEAD)"
printf 'INSTALLER=https://www.radio.studiosatweb.com.br/app/\n'
printf 'WEB_APP=https://www.radio.studiosatweb.com.br/listen/\n'
printf '========================================\n'
