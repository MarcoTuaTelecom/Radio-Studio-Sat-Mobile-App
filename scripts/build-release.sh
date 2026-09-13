#!/usr/bin/env bash
set -Eeuo pipefail

command -v node >/dev/null || { echo 'Node.js ausente'; exit 1; }
command -v npm >/dev/null || { echo 'npm ausente'; exit 1; }

npm install
npx expo install --fix
npx expo-doctor
npm run typecheck

echo
printf '%s\n' 'Validação concluída.'
printf '%s\n' 'APK de teste: npx eas-cli@latest build --platform android --profile preview'
printf '%s\n' 'AAB Play Store: npx eas-cli@latest build --platform android --profile production'
printf '%s\n' 'iOS App Store: npx eas-cli@latest build --platform ios --profile production'
