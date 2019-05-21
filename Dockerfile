# L'image de base
FROM debian:stretch

# Labels
LABEL version="1.0"
LABEL maintainer="christophebarriere@free.fr"
LABEL description="Image Docker pour un OS Debian avec: \
- connexion SSH activé, \
- serveur web Nginx, \
- un volume /site_files qui pourra être monté à aprtir de l'hôte pour modifier dynamiquement notre site"

# Mode non interactif
ENV DEBIAN_FRONTEND noninteractive

# Pas de initrd
ENV INITRD No

# Installation du serveur nginx, du serveur ssh et des locales + nettoyage
RUN apt-get update \
  && apt-get install -y --no-install-recommends nginx openssh-server locales \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Gestion de la locale et de la timezone
RUN ln -fs /usr/share/zoneinfo/Europe/Paris /etc/localtime && dpkg-reconfigure -f noninteractive tzdata && echo fr_FR.UTF-8 UTF-8 > /etc/locale.gen && locale-gen --purge en_US.UTF-8

# Configuration de Nginx (notamment daemon off)
ADD nginx.conf /etc/nginx/nginx.conf

# Le répertoire /site_files du container contiendra les fichiers du site qui sera servi par Nginx, donc on en fait un volume qui sera bind-mounter
VOLUME /site_files

# Il doit y avoir un répertoire /var/run/sshd dans le container pour faire fonctionner le serveur ssh
RUN mkdir /var/run/sshd

# On ajoute sa clé publique dans le serveur
ADD id_rsa.pub /root/.ssh/root-connect_id_rsa.pub
RUN cat /root/.ssh/root-connect_id_rsa.pub > /root/.ssh/authorized_keys

# Pour autoriser le ssh avec l'utilisateur root
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# On expose les ports 22 et 80 du container (on pourra les mapper à partir de l'hôte)
EXPOSE 22 80

# le container est lancé en tant que root
USER root

# On envoie les logs de nginx vers les sorties standards
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

# Ajout de la commande de lancement
ADD container_command.sh /

# Commande de lancement du container (on crée une commande personnalisée pour lancer les deux process nginx (en mode non dameon) et sshd comme enfant du process principal)
CMD ["sh", "/container_command.sh"]
