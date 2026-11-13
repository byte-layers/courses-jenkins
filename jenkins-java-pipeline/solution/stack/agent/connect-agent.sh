#!/bin/bash
# Récupère le secret de cet agent auprès du contrôleur, puis lance l'agent inbound habituel.
# Le contrôleur calcule ce secret à son démarrage : on ne peut pas l'écrire dans compose.yaml.
set -euo pipefail
: "${JENKINS_URL:?}" "${JENKINS_AGENT_NAME:?}"
password=$(cat /run/secrets/agent_connector_password)
url="$JENKINS_URL/computer/$JENKINS_AGENT_NAME/jenkins-agent.jnlp"
until jnlp=$(curl -fsS -u "agent-connector:$password" "$url" 2>/dev/null); do
  echo "waiting for $url ..."
  sleep 5
done
JENKINS_SECRET=$(sed -n 's|.*<application-desc><argument>\([0-9a-f]\{64\}\)</argument>.*|\1|p' <<<"$jnlp")
export JENKINS_SECRET
exec /usr/local/bin/jenkins-agent
