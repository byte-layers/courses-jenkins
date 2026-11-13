FROM jenkins/inbound-agent:3395.v6e5377b_0fb_3c-2-jdk21

USER root
# La CLI Docker et buildx seulement : le moteur est celui de l'hôte, joint par le socket monté.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# Les caches partagés (Maven, grype, syft) : créé ici pour que le volume nommé appartienne à jenkins
RUN install -d -o jenkins -g jenkins /home/jenkins/caches

COPY connect-agent.sh /usr/local/bin/connect-agent.sh
USER jenkins
ENTRYPOINT ["/usr/local/bin/connect-agent.sh"]
