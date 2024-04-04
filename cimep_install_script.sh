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

SITE="crmtest2"
DOSSIER_SITE=$DOSSIER_INSTALL$SITE
ZIP_SITE="cimep.zip"

NODE="$SITE-node"
DOSSIER_NODE=$DOSSIER_INSTALL$NODE
ZIP_NODE="cimep-node.zip"

SCRIPT="$SITE-script"
DOSSIER_SCRIPT=$DOSSIER_INSTALL$SCRIPT
ZIP_SCRIPT="cimep-script.zip"


CERTIFICATS="certificats.tar"
PHPVERSION="7.3"
SITE_NAME="$SITE.fr"

####################################



#1) Update + Installer Apache2, Node JS, PHP, postgresql :


apt-get update && apt full-upgrade -yqq

apt install sudo lsb-release apt-transport-https ca-certificates ssl-cert software-properties-common -yqq
apt install apache2 -yqq
apt install  nodejs npm  -yqq

wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
apt update
apt install unoconv zip acl pdftk -yqq
apt install php$PHPVERSION -yqq
apt install php{-cas,$PHPVERSION-{xmlrpc,zip,pgsql,apcu,bz2,curl,mbstring,intl,json,common,gd,xml}} -yqq


#2) Extraire l'ensemble des fichiers dans un repertoire (exemple : /var/www/cimep-node)

#tar -xf ./$CERTIFICATS -C /etc/apache2/

mkdir -p /etc/apache2/certificat-conf
cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/apache2/certificat-conf/$SITE.key
cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/apache2/certificat-conf/$SITE.pem

#openssl req -new -x509 -days 365 -noenc -out /etc/apache2/certificat-conf/$SITE.pem -keyout /etc/apache2/certificat-conf/$SITE.key

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
npm install


echo '{
  "port": 8043,
  "password": "218df0761c81d63cc75023b9ae2f4567c3a68f03",
  "verbose": "info",
  "ssl": true,
  "ssl_key": "/etc/apache2/certificat-conf/$SITE.key",
  "ssl_crt": "/etc/apache2/certificat-conf/$SITE.pem",
  "default_redirect": "https://$SITE_NAME",
  "main_server_ip": "192.168.40.10"
}' > config.json

echo "
# Real environment variables win over .env files.
#
# DO NOT DEFINE PRODUCTION SECRETS IN THIS FILE NOR IN ANY OTHER COMMITTED FILES.
#
# Run 'composer dump-env prod' to compile .env files for production use (requires symfony/flex >=1.2).
# https://symfony.com/doc/current/best_practices/configuration.html#infrastructure-related-configuration


###> symfony/framework-bundle ###
APP_ENV=dev
APP_SECRET=23d7cb8ed593909b2bcd5836b8dc8a57
#TRUSTED_PROXIES=127.0.0.1,127.0.0.2
#TRUSTED_HOSTS='^localhost|example\.com$'
###< symfony/framework-bundle ###

###> doctrine/doctrine-bundle ###
# Format described at https://www.doctrine-project.org/projects/doctrine-dbal/en/latest/reference/configuration.html#connecting-using-a-url
# For an SQLite database, use: 'sqlite:///%kernel.project_dir%/var/data.db'
# Configure your db driver and server_version in config/packages/doctrine.yaml
DATABASE_URL=pgsql://cimep:12345678@127.0.0.1:5432/cimep
###< doctrine/doctrine-bundle ###

###> symfony/swiftmailer-bundle ###
# For Gmail as a transport, use: 'gmail://username:password@localhost'
# For a generic SMTP server, use: 'smtp://localhost:25?encryption=&auth_mode='
# Delivery is disabled by default via 'null://localhost'
MAILER_URL=smtp://localhost
###< symfony/swiftmailer-bundle ###

APP_LOCALE=fr
EMAIL_ERROR=admin@$SITE.fr
MAILER_FROM=no-reply@$SITE.fr
MAILER_SENDER=CIME-P
HOST=$SITE.fr
SERVER_NODE_LOCATION=app.$SITE.fr
SERVER_NODE_PASSWORD=null
SERVER_FTP_LOCATION=ftp.$SITE.fr
SERVER_FTP_FULL_ENABLE=true
DIR_FTP=/home/ftp
DIR_LARGE_FILES=/var/www/$SITE/var/media/large_files
DIR_DRC_AUTO=/var/www/$SITE/var/media/large_files
DIR_DRM=/var/www/$SITE/var/media/drm
UPDATE_CREDENTIAL=null
" > $DOSSIER_SITE/.env

#3-b) Installer le lanceur automatique :
cd $DOSSIER_NODE
npm install pm2 -g
pm2 start app.js
pm2 startup


### 1.2 - Installation de CIME-P

#4) Installation de la base de donnée

#4-a) Installation de postgresql :

apt install postgresql -yqq
pg_ctlcluster 15 main start


#Par défault, root de postgresql n'a pas de mot de passe.
# Demander à l'utilisateur de saisir le nouveau mot de passe

#echo "Entrez le nouveau mot de passe pour l'utilisateur root de PostgreSQL :"
#read -s new_password
new_password="12345678"

# Définir le mot de passe en utilisant la commande psql
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '12345678';"

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
hostssl cimep          cimep          0.0.0.0/0               scram-sha-256
hostssl cimep          cimep          ::/0                    scram-sha-256
" >> /etc/postgresql/15/main/pg_hba.conf



## Définir la configuration globale de postgresql dans /etc/postgresql/X/main/postgresql.conf :

echo "listen_addresses = '*'" >> /etc/postgresql/15/main/postgresql.conf
echo "password_encryption = scram-sha-256" >> /etc/postgresql/15/main/postgresql.conf
systemctl restart postgresql

## Création d'un nouvel utilisateur de base de donnée "cimep" et sa base de donnée "cimep"  

   sudo -u postgres psql -c "CREATE USER cimep WITH PASSWORD '12345678';"
   sudo -u postgres psql -c "CREATE DATABASE cimep ENCODING 'UTF8' OWNER cimep TEMPLATE template0;"



## Modifier les deux php.ini /etc/php/X/apache2/php.ini et /etc/php/X/cli/php.ini


sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/7.3/apache2/php.ini
sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/7.3/cli/php.ini

echo ""
echo "#### Modification php.ini OK ######"
echo ""

echo "<VirtualHost *:80>

            ServerName      $SITE_NAME
            ServerAdmin     admin@$SITE_NAME
            RewriteEngine on
            RewriteCond %{SERVER_NAME} =https://$SITE_NAME [OR]
            RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]

    </VirtualHost>

    <VirtualHost *:443>

            ServerName      $SITE_NAME
            ServerAdmin     admin@$SITE_NAME

            DocumentRoot /var/www/$SITE/public

            <Directory /var/www/$SITE/public>
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
            SSLCertificateFile /etc/apache2/certificat-conf/$SITE.pem
            SSLCertificateKeyFile /etc/apache2/certificat-conf/$SITE.key
            #SSLCertificateChainFile /etc/apache2/certificat-conf/$SITE.pem
            SSLProtocol all -SSLv2 -SSLv3

           # SSLCertificateFile /etc/ssl/www/$SITE_NAME/cert.crt
           # SSLCertificateKeyFile /etc/ssl/www/$SITE_NAME/cert.key
           # SSLCertificateChainFile /etc/ssl/www/$SITE_NAME/fullchain.pem
    </VirtualHost>" > /etc/apache2/sites-available/$SITE.conf

# Penser à insérer les certificats ssl dans /etc/ssl/www/
#mkdir -p /etc/ssl/www/$SITE_NAME

# Activer le site :

a2enmod ssl
a2enmod rewrite
a2enmod headers
a2ensite $SITE.conf
systemctl restart apache2.service

echo ""
echo "#### Restart APACHE OK ######"
echo ""

# Fixer les droits :
chown -R www-data:www-data /var/www
chmod -R 775 /var/www

echo ""
echo "#### Modification droits /var/www OK ######"
echo ""


# Rajouter la ligne suivante dans le fichier /etc/hosts (adapter l'url) :

echo "127.0.0.1   app.$SITE_NAME $SITE" > /etc/hosts
echo "192.168.40.10   app.$SITE_NAME $SITE" >> /etc/hosts
# *Ceci afin que le mode de maintenance ne bloque pas les requêtes du serveur vers lui même*
# Installation des dépendances requise pour cimep

cd $DOSSIER_SITE
sudo -u www-data php composer.phar install --no-scripts

echo ""
echo "#### Modification php.ini OK ######"
echo ""


#Créer et configurer le .env
sudo -u www-data php composer.phar dump-env prod

echo ""
echo "#### composer.phar + dump OK ######"
echo ""


sudo -u www-data nano .env.local.php

echo ""
echo "#### .env.local.php OK ######"
echo ""

# Se référer au chapitre 2 pour la correspondance des paramètres du fichier de configuration.
#**Si une base de donnée existe déjà, il faut dès maintenant l'importer** (voir chapitre 3.2 - Importer une base de donnée sur une base vierge) lors de l'execution de la prochaine commande, ne pas importer les données de base (le choix sera proposé).  
#Il faut aussi copier le contenu de var/media de la précédente installation sur la nouvelle installation.

sudo ./installer install

echo ""
echo "#### ./installer OK ######"
echo ""

### FIN POUR TEST !! ###
