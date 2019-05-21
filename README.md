# Fonctionnalités

On veut lancer un serveur Debian dans un container docker avec les services ssh et nginx.

Voilà les fonctionnalités souhaitées:
- on doit se logguer en ssh avec une clé privée
- on doit pouvoir modifier les fichers du site web sans entrer dans le container


# Détail du Dockerfile

1. On part donc de l'image de base debian:stretch pour construire l'image
   ```
   FROM debian:stretch
   ```

2. On ajoute des étiquettes à notre image :
   ```
   LABEL version="1.0"
   LABEL maintainer="christophebarriere@free.fr"
   LABEL description="Image Docker pour un OS Debian avec: \
   - connexion SSH activé, \
   - serveur web Nginx, \
   - un volume /site_files qui pourra être monté à aprtir de l'hôte pour modifier dynamiquement notre site"
   ```


3. L'installation est automatique donc on ne veut pas que debconf pose des quetions lors de l'installation ou la configuration de paquets :
   ```
   ENV DEBIAN_FRONTEND noninteractive
   ```

4. On ne veut pas de bootloader :
   ```
   ENV INITRD No
   ```

5. On met à jour la liste des paquets, on installe nginx, openssh-server et les locales sans demander de confirmation (option -y), sans installer les paquets recommandés en plus (option --no-install-recommends) pour pouvoir limiter la taille de l'image et on nettoie le cache apt (également pour limiter la taille de l'image)
   ```
   RUN apt-get update \
     && apt-get install -y --no-install-recommends nginx openssh-server locales \
     && apt-get clean \
     && rm -rf /var/lib/apt/lists/*
   ```
   NB: Tout en une seule commande Dockerfile pour pouvoir optimiser les couche de notre image.

6. Gestion de la locale (fr_FR.UTF-8) et de la timezone (Europe/Paris) :
   ```
   RUN ln -fs /usr/share/zoneinfo/Europe/Paris /etc/localtime && dpkg-reconfigure -f noninteractive tzdata && echo fr_FR.UTF-8 UTF-8 > /etc/locale.gen && locale-gen --purge en_US.UTF-8
   ```

7. Ajout de la configuration nginx dans l'image :
   ```
   ADD nginx.conf /etc/nginx/nginx.conf
   ```
   NB: deux choses importantes dans cette configuration :
   - les fichiers du site seront dans le répertoire `/site_files` du container
   - nginx sera démarré en mode daemon off pour qu'il reste au premier plan afin que docker puisse suivre correctement le processus (sinon le conteneur s'arrêtera immédiatement après le démarrage)

8. On veut un volume docker pour la persistence des données du site (le répertoire qui contient les fichiers servis par Nginx) :
   ```
   VOLUME /site_files
   ```
   NB : le mieux sera de faire un montage de type bind sur ce volume lorqu'on lancera le container car de cette façon on pourra modifier les ficheirs du site web directement dans l'hôte et non pas dans le container).

9. Il doit y avoir un répertoire /var/run/sshd pour le pidfile du serveur ssh :
   ```
   RUN mkdir /var/run/sshd
   ```

10. On ajoute notre clé publique pour que l'utilisateur root puisse se connecter avec sa clé privée en ssh :
   ```
   ADD id_rsa.pub /root/.ssh/root-connect_id_rsa.pub
   RUN cat /root/.ssh/root-connect_id_rsa.pub > /root/.ssh/authorized_keys
   ```

11. On modifie la configuration du serveur SSH pour autoriser root à se logguer en SSH :
   ```
   RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
   ```
   NB: J'ai fait simple. Idéalement il faudrait créer un nouvel utilisateur avec les droits sudo.

12. On expose le port 22 (port pour le SSH) et le port 80 (pour nginx) dans le container :
   ```
   EXPOSE 22 80
   ```
   NB : Il fadra mapper correctement ces ports lorsqu'on lance le container. En effet le port 22b par exemple est déjà utilisé dans la machine hôte

13. Le container sera lancé par l'utilisateur root :
   ```
   USER root
   ```

14. On redirige les logs de nginx vers les sorties standards (de cette façon on pourra voir les logs avec la commande `docker logs <nom_du_container>`) :
   ```
   RUN ln -sf /dev/stdout /var/log/nginx/access.log \
   	&& ln -sf /dev/stderr /var/log/nginx/error.log
   ```

15. On ajoute la commande de lancement à la racine du container :
   ```
   ADD container_command.sh /
   ```
   NB : cette commande lancera dans un même processus (que docker peut suivre) à la fois le serveur ssh et le serveur nginx

16. On definit la commande de lancement du container :
   ```
   CMD ["sh", "/container_command.sh"]
   ```

# Construction de l'image
Dans le répertoire de notre projet, il faut lancer la commande suivante :

`docker build --rm -t registry.docker.charloup.test:5000/nginx_with_ssh:1 .`

Explications :
- option `--rm` : permet de supprimer les images intermédiaires après un build réussi
- option `-t` pour donner un nom à mon image (j'ai mis ma registry comme ça je pourrai la pousser par la suite avec `docker push registry.docker.charloup.test:5000/nginx_with_ssh:1`)
- on envoie le répertoire courant comme contexte pour construire l'image

# Lancement du container
Dans le répertoire de notre projet, il faut lancer la commande suivante :

`docker run -d -p 2222:22 -p 8080:80 --mount type=bind,source="$(pwd)"/site_files,target=/site_files --name nginx_ssh registry.docker.charloup.test:5000/nginx_with_ssh:1`

Explications :
- option `-d` : lancement en mode détaché
- option `-p 2222:22` : on mappe le port 22 du container sur le port 2222 de notre machine hôte. De cette manière on pourra se connecter en ssh dans le container en utilisant localhost sur le port 2222
- option `-p 8080:80` : on mappe le port 80 du container sur le port 8080 de la machine hôte. Notre serveur web nginx dans le container sera donc accessible via http://localhost:8080 dans la machine hôte
- option `--mount type=bind,source="$(pwd)"/site_files,target=/site_files` : on monte le répertoire site_files de notre machine hôte dans le répertoire `/site_files` du container (celui qui est servi par nginx)
- option `--name nginx_ssh` : on donne un nom au container. Par exemple ensuite pour voir les processus qui tournent dans le container, on fait `docker top nginx_ssh`
- on lance le container à partir de l'image `registry.docker.charloup.test:5000/nginx_with_ssh:1` précédemment construite

# Vérification
- Site web : `curl http://localhost:8080` nous retourne `Ceci est l'index de mon site servi Nginx dans un container Docker` qui est le contenu de mon fichier site_files/index.html dans la machine hôte
- Modification du site : `echo 'Mes modifications' > ./site_files/index.html && curl http://localhost:8080` m'affiche bien `Mes modifications`
- Connexion ssh : `ssh -i chemin_vers_ma_cle_privee root@localhost -p 2222` => OK on est bien connecté en ssh dans le container

# Remarques
- Un container avec ssh n'est pas forcément nécessaire. Si il y a bash dans le container, on peut faire `docker exec -it nom_du_container bash` pour se connecter dans un container qui est démarré.
- Je peux lancer mon container pour être servi par traefik afin de ne pas avoir à mapper le port 80 du container. Voilà la commande à utiliser: `docker run -d -p 2222:22 --mount type=bind,source="$(pwd)"/site_files,target=/site_files --name nginx_ssh --network=traefik-net --label traefik.enable=true --label traefik.frontend.entryPoints=http --label traefik.frontend.rule=Host:nginx.charloup.test --label traefik.port=80 --label traefik.backend=nginx registry.docker.charloup.test:5000/nginx_with_ssh:1` et on vérifie que cela fonctionne avec `curl -H "Host:nginx.charloup.test" localhost`
