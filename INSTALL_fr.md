# INSTRUCTIONS D'INSTALLATION

## RosarioSIS Student Information System

RosarioSIS est une application web qui dépend d'un serveur web, du langage de script PHP et d'un serveur de base de données PostgreSQL ou MySQL/MariaDB.

Pour que RosarioSIS fonctionne, vous devrez d'abord avoir votre serveur web, PostgreSQL (ou MySQL/MariaDB) et PHP (extensions `pgsql`, `mysqli`, `pdo`, `gettext`, `intl`, `mbstring`, `gd`, `curl`, `xml` & `zip` incluses) en état de marche. L'installation et la configuration des ces derniers varie selon votre système d'exploitation aussi ne seront-elles pas couvertes ici.

RosarioSIS a été testé sur:

- Windows 10 avec Apache 2.4.58, MariaDB 10.4.32, et PHP 8.1.25
- macOS Monterey avec Apache 2.4.54, Postgres 14.4, et PHP 8.0.21
- Ubuntu 24.04 avec Apache 2.4.52, MySQL 8.0.41, et PHP 5.6.40
- Ubuntu 22.04 avec Apache 2.4.57, Postgres 14.9, et PHP 8.1.2
- Debian Bookworm avec Apache 2.4.57, Postgres 15.5, MariaDB 10.11.4, et PHP 8.3.10
- Hébergement mutualisé avec cPanel, nginx, Postgres 9.2, et PHP 7.2
- à travers Mozilla Firefox et Google Chrome
- à travers BrowserStack pour la compatibilité navigateurs (incompatible avec Internet Explorer)

Minimum requis: [PHP](https://www.php.net/supported-versions.php) 5.5.9 & [PostgreSQL](https://www.postgresql.org/support/versioning/) 9.2 or [MySQL](https://en.wikipedia.org/wiki/MySQL#Release_history) 5.6/[MariaDB](https://mariadb.com/kb/en/mariadb-releases/)

Instructions d'installation pour:

- [**Windows**](https://gitlab.com/francoisjacquet/rosariosis/wikis/Installer-RosarioSIS-sur-Windows)
- [**Mac**](https://gitlab.com/francoisjacquet/rosariosis/-/wikis/How-to-install-RosarioSIS-on-Mac-(macOS,-OS-X)) (en anglais)
- [**cPanel**](https://gitlab.com/francoisjacquet/rosariosis/wikis/How-to-install-RosarioSIS-on-cPanel) (en anglais)
- [**Softaculous**](https://gitlab.com/francoisjacquet/rosariosis/-/wikis/How-to-install-RosarioSIS-with-Softaculous) (en anglais)
- [**Docker**](https://gitlab.com/francoisjacquet/docker-rosariosis/) (en anglais)
- **Ubuntu** (ou n'importe quelle distribution Linux basée sur Debian), voir ci-dessous

Si vous ne disposez pas des moyens techniques ou des compétences pour installer RosarioSIS, vous pouvez souscrire à une offre hébergée sur https://www.rosariosis.com/fr


Installer le paquet
-------------------

Décompressez la [dernière version](https://www.rosariosis.org/fr/download/) de RosarioSIS, ou bien clonez le dépôt git (et faites le checkout du tag de la [dernière version](https://gitlab.com/francoisjacquet/rosariosis/-/releases)) dans un répertoire accessible depuis le navigateur. Éditez le fichier `config.inc.sample.php` afin de régler les variables de configuration et renommez-le `config.inc.php`.

- `$DatabaseType` Type du serveur de base de données: mysql ou postgresql.
- `$DatabaseServer` Nom de l'hôte ou IP du serveur de base de données.
- `$DatabaseUsername` Nom d'utilisateur pour se connecter à la base de données.
- `$DatabasePassword` Mot de passe pour se connecter à la base de données.
- `$DatabaseName` Nom de la base de données.

- `$DatabaseDumpPath` Chemin complet vers l'utilitaire d'export de base de donnée, pg_dump (PostgreSQL), mysqldump (MySQL) ou mariadb-dump (MariaDB).
- `$wkhtmltopdfPath` Chemin complet vers l'utilitaire de génération de PDF, wkhtmltopdf.

- `$DefaultSyear` Année scolaire par défaut. Ne changer qu'après avoir lancé le programme _Report final_. NE PAS changer à l'installation.
- `$RosarioNotifyAddress` Adresse email pour les notifications (nouvel administrateur, nouvel élève / utilisateur, nouvelle inscription).
- `$RosarioLocales` Liste des codes de langues séparés par des virgules. Voir le dossier `locale/` pour les codes disponibles.

#### Variables optionelles

- `$DatabasePort` Numéro du port pour accéder au serveur de base de données. Défaut : 5432 pour PostgreSQL et 3306 pour MySQL.
- `$RosarioPath` Chemin complet vers l'installation de RosarioSIS.
- `$StudentPicturesPath` Chemin vers les photos des élèves.
- `$UserPicturesPath` Chemin vers les photos des utilisateurs.
- `$FileUploadsPath` Chemin vers les fichiers uploadés.
- `$LocalePath` Chemin vers les packs de langue. Redémarrer Apache après modification.
- `$PNGQuantPath` Chemin vers [PNGQuant](https://pngquant.org/) (compression des images PNG).
- `$RosarioErrorsAddress` Adresse email pour les erreurs (PHP fatal, base de donnée, tentatives de piratage).
- `$Timezone` Fuseau horaire utilisé par les fonctions de date/heure. [Liste des Fuseaux Horaires Supportés](http://php.net/manual/fr/timezones.php).
- `$ETagCache` Passer à `false` pour désactiver le [cache ETag](https://fr.wikipedia.org/wiki/Balise-entit%C3%A9_ETag_HTTP) et le cache de session "privée". Voir [Sessions et sécurité](https://secure.php.net/manual/fr/session.security.php).
- `define( 'ROSARIO_POST_MAX_SIZE_LIMIT', 16 * 1024 * 1024 );` Limiter la taille de `$_POST` (16MB par défaut). Détails [ici](https://gitlab.com/francoisjacquet/rosariosis/-/blob/mobile/Warehouse.php#L322).
- `define( 'ROSARIO_DEBUG', true );` Mode debug activé.
- `define( 'ROSARIO_DISABLE_ADDON_UPLOAD', true );` Désactiver l'upload de compléments (modules et plugins).
- `define( 'ROSARIO_DISABLE_ADDON_DELETE', true );` Désactiver la possibilité de supprimer les compléments (modules & plugins).
- `define( 'ROSARIO_DISABLE_USAGE_STATISTICS', true );` Désactiver la collecte de statistiques d'usage.


Créer la base de données
------------------------

Vous êtes maintenant prêt pour configurer la base de données de RosarioSIS. Si vous avez accès à l'invite de commande sur votre serveur, ouvrez une fenêtre de terminal et suivez ces instructions.

Les instructions suivantes sont pour **PostgreSQL** (voir plus bas pour MySQL) :

1. Connectez-vous à PostgreSQL avec l'utilisateur postgres :
```bash
server$ sudo -u postgres psql
```
2. Créez l'utilisateur rosariosis :
```bash
postgres=# CREATE USER rosariosis_user WITH PASSWORD 'rosariosis_user_password';
```
3. Créez la base de données rosariosis :
```bash
postgres=# CREATE DATABASE rosariosis_db WITH ENCODING 'UTF8' OWNER rosariosis_user;
```
4. Déconnexion de PostgreSQL :
```bash
postgres=# \q
```

Aussi, vous devrez peut-être éditer le fichier [`pg_hba.conf`](http://www.postgresql.org/docs/current/static/auth-pg-hba-conf.html) afin d'autoriser la connexion d'utilisateur par mot de passe (`md5`):
```
# "local" is for Unix domain socket connections only
local   all             all                                     md5
```

---------------------------------------------

Les instructions suivantes sont pour **MySQL** :

1. Connectez-vous à MySQL avec l'utilisateur root :
```bash
server$ sudo mysql
```
ou bien
```bash
server$ mysql -u root -p
```
2. Permettre la création de fonctions :
```bash
mysql> SET GLOBAL log_bin_trust_function_creators=1;
```
3. Créez l'utilisateur rosariosis :
```bash
mysql> CREATE USER 'rosariosis_user'@'localhost' IDENTIFIED BY 'rosariosis_user_password';
```
4. Créez la base de données rosariosis :
```bash
mysql> CREATE DATABASE rosariosis_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
mysql> GRANT ALL PRIVILEGES ON rosariosis_db.* TO 'rosariosis_user'@'localhost';
```
5. Déconnexion de MySQL :
```bash
mysql> \q
```


Installer la base de données
----------------------------

Pour installer la base de données, pointez votre navigateur sur : `http://votredomaine.com/REPERTOIRE_DINSTALLATION/InstallDatabase.php`

C'est tout !... maintenant, pointez votre navigateur sur : `http://votredomaine.com/REPERTOIRE_DINSTALLATION/index.php`

et connectez-vous avec le nom d'utilisateur 'admin' et le mot de passe 'admin'. Avec cet utilisateur, vous pourrez créer de nouveaux utilisateurs, et modifier ou supprimer les trois utilisateurs type.


Problèmes
---------

Afin de vous aider à identifier les problèmes, pointez votre navigateur sur : `http://votredomaine.com/REPERTOIRE_DINSTALLATION/diagnostic.php`


Extensions PHP
--------------

Instructions d'installation pour Ubuntu 22.04 :
```bash
server$ sudo apt-get install php-pgsql php-mysql php-pdo php-intl php-mbstring php-gd php-curl php-xml php-zip
```


php.ini
-------

Configuration de PHP recommandée. Editez le fichier [`php.ini`](https://www.php.net/manual/fr/ini.list.php) comme suit :
```
; Maximum time in seconds a PHP script is allowed to run
max_execution_time = 240

; Maximum accepted input variables ($_GET, $_POST)
; 4000 allows submitting lists of up to 1000 elements, each with multiple inputs
max_input_vars = 4000

; Maximum memory (RAM) allocated to a PHP script
memory_limit = 512M

; Session timeout: 1 hour
session.gc_maxlifetime = 3600

; Maximum allowed size for uploaded files
upload_max_filesize = 50M

; Must be greater than or equal to upload_max_filesize
post_max_size = 51M
```
Redémarrer PHP et Apache.


Autres langues
--------------

Instructions d'installation pour Ubuntu. Installer la locale français (France) :
```bash
server$ echo "fr_FR.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen
server$ sudo locale-gen
server$ sudo update-locale
```
Ensuite redémarrez le serveur.


[wkhtmltopdf](http://wkhtmltopdf.org/)
--------------------------------------

Instructions d'installation pour Ubuntu 22.04 (jammy), fonctionne aussi pour Ubuntu 24.04 (noble) :
```bash
server$ wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
server$ sudo apt install ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb
server$ wkhtmltopdf --version
server$ wkhtmltopdf 0.12.6.1 (with patched qt)
```

Définir le chemin dans le fichier `config.inc.php` :
    `$wkhtmltopdfPath = '/usr/local/bin/wkhtmltopdf';`


Envoi d'email
-------------

Instructions d'installation pour Ubuntu. Activer la fonction `mail()` de PHP :
```bash
server$ sudo apt-get install sendmail
```


Configuration additionnelle
---------------------------

[Guide de Configuration Rapide](https://www.rosariosis.org/fr/quick-setup-guide/)

[Sécuriser RosarioSIS](https://gitlab.com/francoisjacquet/rosariosis/-/wikis/Secure-RosarioSIS)
