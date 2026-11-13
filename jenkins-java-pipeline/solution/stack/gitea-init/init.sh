#!/bin/bash
# Lancé une fois : crée le compte learner, importe spring-petclinic à un commit précis, ajoute le webhook vers Jenkins.
set -euo pipefail
GITEA=http://gitea:3000
PASS=$(cat /run/secrets/gitea_password)
PETCLINIC_URL=https://github.com/spring-projects/spring-petclinic.git
PETCLINIC_COMMIT=500158f

su-exec git gitea --config /data/gitea/conf/app.ini admin user create \
  --username learner --password "$PASS" --email learner@example.test --admin --must-change-password=false \
  || echo "user learner already exists"

api() { curl -fsS -u "learner:$PASS" -H 'Content-Type: application/json' "$@"; }

if ! api "$GITEA/api/v1/repos/learner/spring-petclinic" >/dev/null 2>&1; then
  api -X POST "$GITEA/api/v1/user/repos" -d '{"name":"spring-petclinic","default_branch":"main","private":false}' >/dev/null
  work=$(mktemp -d)
  if [ -d /seed/spring-petclinic/.git ]; then
    git clone -q /seed/spring-petclinic "$work/petclinic"      # copie hors ligne, si elle est fournie
  else
    git clone -q "$PETCLINIC_URL" "$work/petclinic"
  fi
  git -C "$work/petclinic" checkout -q -B main "$PETCLINIC_COMMIT"
  git -C "$work/petclinic" push -q "http://learner:$PASS@gitea:3000/learner/spring-petclinic.git" main
  echo "spring-petclinic imported at $PETCLINIC_COMMIT"
fi

if ! api "$GITEA/api/v1/repos/learner/spring-petclinic/hooks" | grep -q gitea-webhook; then
  api -X POST "$GITEA/api/v1/repos/learner/spring-petclinic/hooks" -d '{
    "type":"gitea","active":true,
    "events":["push","create","delete","pull_request"],
    "config":{"url":"http://jenkins:8080/gitea-webhook/post","content_type":"json"}}' >/dev/null
  echo "webhook to Jenkins created"
fi
