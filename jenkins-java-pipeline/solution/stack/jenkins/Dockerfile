FROM jenkins/jenkins:2.580.2-lts-jdk21

# Les plugins sont installés à la construction de l'image : ils sont là au premier démarrage, sans assistant.
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/casc
