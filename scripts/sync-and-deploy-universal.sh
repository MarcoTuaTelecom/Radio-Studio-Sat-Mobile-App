#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-/root/Radio-Studio-Sat-Mobile-App}"
KEY="${KEY:-/root/.ssh/id_ed25519_studiosat_mobile}"
VERSION="${VERSION:-1.1.0}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="/root/studiosat-git-backups/$TS"
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

ok(){ printf '\nPASS  %s\n' "$*"; }
fail(){ printf '\nFAIL  %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "execute como root"
[[ -f "$KEY" ]] || fail "chave GitHub ausente: $KEY"
[[ -d "$REPO/.git" ]] || fail "repositorio ausente: $REPO"
cd "$REPO"

printf '\n===== A. GIT LOCAL =====\n'
git config core.fileMode false
git config core.sshCommand "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
DIRTY="$(git status --porcelain)"
if [[ -n "$DIRTY" ]]; then
  mkdir -p "$BACKUP_DIR"
  git status --short | tee "$BACKUP_DIR/status.txt"
  git diff > "$BACKUP_DIR/worktree.patch" || true
  git diff --cached > "$BACKUP_DIR/index.patch" || true
  git stash push -u -m "studiosat-auto-backup-$TS"
  echo "LOCAL_BACKUP=$BACKUP_DIR"
fi
ok "worktree segura"

printf '\n===== B. GITHUB =====\n'
SSH_OUT="$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com 2>&1 || true)"
printf '%s\n' "$SSH_OUT"
grep -qi 'successfully authenticated' <<<"$SSH_OUT" || fail "GitHub SSH nao autenticou"
git fetch origin main
git checkout main
git pull --ff-only origin main
ok "main sincronizada: $(git rev-parse --short HEAD)"

printf '\n===== C. VALIDACAO DE CODIGO =====\n'
for f in scripts/deploy-universal-platforms.sh scripts/deploy-download-page.sh scripts/fix-hls-cors.sh; do
  [[ -f "$f" ]] || fail "arquivo ausente: $f"
  bash -n "$f"
done
python3 -m py_compile scripts/generate-pwa-icons.py
npm install --no-audit --no-fund
npx --yes expo-doctor
npm run typecheck
ok "Expo Doctor + TypeScript"

printf '\n===== D. DEPLOY SEM REESCREVER NGINX =====\n'
VERSION="$VERSION" bash scripts/deploy-universal-platforms.sh
ok "web/PWA do modelo publicado"

printf '\n========================================\n'
printf 'SYNC_AND_DEPLOY=PASS\n'
printf 'HEAD=%s\n' "$(git rev-parse HEAD)"
printf 'UI_VERSION=%s\n' "$VERSION"
printf 'INSTALLER=https://www.radio.studiosatweb.com.br/app/\n'
printf 'APP=https://www.radio.studiosatweb.com.br/listen/\n'
printf 'NEXT_ANDROID_BUILD=VERSION=%s bash scripts/build-release.sh preview\n' "$VERSION"
printf '========================================\n'
