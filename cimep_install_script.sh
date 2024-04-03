#!/bin/bash

if (whoami != root)
  then echo "Please run as root"
  exit

fi



## 1 - Installation
#
# Attention, CIME-P nécessite au minimum php en version 7.3 pour toutes les version >= 0.6.X
#
### 1.1 - Installation du serveur node

######### VARIABLE ##############
DOSSIER_INSTALL="/var/www/"

DOSSIER_SITE=$DOSSIER_INSTALL"crmtest"
ZIP_SITE="cimep.zip"

DOSSIER_NODE=$DOSSIER_INSTALL"crmtest-node"
ZIP_NODE="cimep-node.zip"

DOSSIER_SCRIPT=$DOSSIER_INSTALL"crmtest-script"
ZIP_SCRIPT="cimep-script.zip"

CERTIFICATS="certificats.zip"
PHPVERSION="7.3"
SITE_NAME="crmtest.fr"

#1) Update + Installer Apache2, Node JS, PHP, postgresql :


apt-get update && apt full-upgrade -y

apt install sudo lsb-release apt-transport-https ca-certificates software-properties-common -y
apt install apache2 -y
apt install  nodejs npm  -y

wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
apt update
apt install unoconv zip acl pdftk
apt install php$PHPVERSION -y
apt install php{-cas,$PHPVERSION-{xmlrpc,zip,pgsql,acpu,bz2,curl,mbstring,intl,json,common,gd,xml}} -y


#2) Extraire l'ensemble des fichiers dans un repertoire (exemple : /var/www/cime-p-node)

unzip ./$CERTIFICATS -d /etc/apache2/

mkdir $DOSSIER_SITE
unzip ./$ZIP_SITE -d $DOSSIER_SITE

mkdir $DOSSIER_SCRIPT
unzip ./$ZIP_SCRIPT -d $DOSSIER_SCRIPT

mkdir $DOSSIER_NODE
unzip ./$ZIP_NODE -d $DOSSIER_NODE


#3) Installer l'application :

#3-a) Configurer l'application node dans le fichier config.json :

cd $DOSSIER_NODE
cp config.json.dist config.json

echo '{
  "port": 8043,
  "password": "218df0761c81d63cc75023b9ae2f4567c3a68f03",
  "verbose": "info",
  "ssl": true,
  "ssl_key": "/etc/apache2/certificat-conf/CRM-CIME-P_cime_g-inp_fr.key",
  "ssl_crt": "/etc/apache2/certificat-conf/crm-cime-p/crm-cime-p_cime_g-inp_fr.crt",
  "default_redirect": "https://crmtest.fr",
  "main_server_ip": "127.0.0.1"
}' > config.json



#3-b) Installer le lanceur automatique :

npm install pm2 -g
pm2 start app.js
pm2 startup


### 1.2 - Installation de CIME-P

#4) Installation de la base de donnée

#4-a) Installation de postgresql :

apt install postgresql -y


#Par défault, root de postgresql n'a pas de mot de passe.
# Demander à l'utilisateur de saisir le nouveau mot de passe

echo "Entrez le nouveau mot de passe pour l'utilisateur root de PostgreSQL :"
read -s new_password

# Définir le mot de passe en utilisant la commande psql
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$new_password';"

# Vérifier si la commande s'est exécutée avec succès
if [ $? -eq 0 ]; then
    echo "Mot de passe root PostgreSQL mis à jour avec succès."
else
    echo "Erreur lors de la mise à jour du mot de passe root PostgreSQL."
    exit
fi


## Définir les règles d'ouverture de postgresql dans /etc/postgresql/X/main/pg_hba.conf :
# Documentation :
# local      DATABASE  USER  METHOD  [OPTIONS]
# host       DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostssl    DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
# hostnossl  DATABASE  USER  ADDRESS  METHOD  [OPTIONS]

PSQL_VERSION=$(echo "ls /etc/postgresql/")

echo "
local all all scram-sha-256              # Autoriser tout les utilisateurs postgresql à se connecter avec un socket Unix
host all all 127.0.0.1/32 scram-sha-256  # Autoriser tout les utilisateurs postgresql à se connecter en TCP-IP depuis la machine locale uniquement
host all all ::1/128 scram-sha-256       # Idem en version IPV6
hostssl cime-p cime-p 0.0.0.0/0 scram-sha-256  # Autoriser seulement l'utilisateur cime-p à se connecter sur la base cime-p en TCP-IP protégé par SSL depuis l'exterieur. Nécessite de configurer le champ listen_address (voir ci-dessous)
hostssl cime-p cime-p ::/0 scram-sha-256     # Idem en version IPV6
" >> /etc/postgresql/$PSQL_VERSION/main/pg_hba.conf



## Définir la configuration globale de postgresql dans /etc/postgresql/X/main/postgresql.conf :

echo "listen_addresses = '*'" >> /etc/postgresql/$PSQL_VERSION/main/postgresql.conf
echo "password_encryption = md5" >> /etc/postgresql/$PSQL_VERSION/main/postgresql.conf
systemctl restart postgresql

## Création d'un nouvel utilisateur de base de donnée "cime-p" et sa base de donnée "cime-p"  

   sudo -u postgres psql -c "CREATE USER cime_p WITH PASSWORD '12345678';"
   sudo -u postgres psql -c "CREATE DATABASE cime_p ENCODING 'UTF8' OWNER cime_p TEMPLATE template0;"



## Modifier les deux php.ini /etc/php/X/apache2/php.ini et /etc/php/X/cli/php.ini


sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/$PHPVERSION/apache2/php.ini
sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/$PHPVERSION/cli/php.ini




echo "<VirtualHost *:80>

            ServerName      $SITE_NAME
            ServerAdmin     admin@$SITE_NAME
            Redirect / $SITE_NAME
            RewriteEngine on
            RewriteCond %{SERVER_NAME} =https://$SITE_NAME [OR]
            RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]

    </VirtualHost>

    <VirtualHost *:443>

            ServerName      $SITE_NAME
            ServerAdmin     admin@$SITE_NAME

            DocumentRoot /var/www/cime-p/public

            <Directory /var/www/cime-p/public>
                    Options Indexes FollowSymLinks MultiViews
                    AllowOverride All
                    Order allow,deny
                    allow from all
                    Directoryindex index.php
            </Directory>

            LogLevel warn

            ErrorLog ${APACHE_LOG_DIR}/$SITE_NAME.error.log
            CustomLog ${APACHE_LOG_DIR}/$SITE_NAME.access.log combined


            SSLEngine on

            SSLProtocol             all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
            SSLCipherSuite          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
            SSLHonorCipherOrder     off
            SSLSessionTickets       off

            SSLOptions +StrictRequire
            SSLCertificateFile /etc/apache2/certificat-conf/crm-cime-p/crm-cime-p_cime_g-inp_fr.crt
            SSLCertificateKeyFile /etc/apache2/certificat-conf/CRM-CIME-P_cime_g-inp_fr.key
            SSLCertificateChainFile /etc/apache2/certificat-conf/crm-cime-p/DigiCertCA.crt
            SSLProtocol all -SSLv2 -SSLv3

           # SSLCertificateFile /etc/ssl/www/$SITE_NAME/cert.crt
           # SSLCertificateKeyFile /etc/ssl/www/$SITE_NAME/cert.key
           # SSLCertificateChainFile /etc/ssl/www/$SITE_NAME/fullchain.pem
    </VirtualHost>" > /etc/apache2/sites-available/cime-p.conf

# Penser à insérer les certificats ssl dans /etc/ssl/www/
#mkdir -p /etc/ssl/www/$SITE_NAME

# Activer le site :

a2enmod ssl
a2enmod rewrite
a2enmod headers
a2ensite cime-p.conf
systemctl restart apache2

# Fixer les droits :

chown -R www-data:www-data /var/www/cime-p
chmod -R 775 /var/www/cime-p

# Rajouter la ligne suivante dans le fichier /etc/hosts (adapter l'url) :

echo "192.168.40.10   $SITE_NAME" >> /etc/hosts

# *Ceci afin que le mode de maintenance ne bloque pas les requêtes du serveur vers lui même*
# Installation des dépendances requise pour cime-p

cd $DOSSIER_INSTALL
sudo -u www-data php composer.phar install --no-scripts

#Créer et configurer le .env
sudo -u www-data php composer.phar dump-env prod
sudo -u www-data nano .env.local.php


# Se référer au chapitre 2 pour la correspondance des paramètres du fichier de configuration.
#**Si une base de donnée existe déjà, il faut dès maintenant l'importer** (voir chapitre 3.2 - Importer une base de donnée sur une base vierge) lors de l'execution de la prochaine commande, ne pas importer les données de base (le choix sera proposé).  
#Il faut aussi copier le contenu de var/media de la précédente installation sur la nouvelle installation.

sudo ./installer install


### FIN POUR TEST !! ###
