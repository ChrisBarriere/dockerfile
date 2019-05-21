#!/bin/bash
echo "Démarrage de sshd"
/usr/sbin/sshd
echo "Démarrage de nginx"
/usr/sbin/nginx
echo "Le serveur est prêt"
