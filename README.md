# Librairies CORE Perl

- [Dépendances](#dépendances)
- [Installation](#installation)
- [Utilisation en submodule GIT](#utilisation-en-submodule-git)
- [Variables d'environnement utilisées dans les librairies](#variables-denvironnement-utilisées-dans-les-librairies)

## Dépendances

* Paquets debian
    * perl-base
    * libgdal-perl
    * libpq-dev
    * gdal-bin
    * libfile-find-rule-perl
    * libfile-copy-link-perl
    * libconfig-ini-perl
    * libdbi-perl
    * libdbd-pg-perl
    * libdevel-size-perl
    * libdigest-sha-perl
    * libfile-map-perl
    * libfindbin-libs-perl
    * libhttp-message-perl
    * liblwp-protocol-https-perl
    * libmath-bigint-perl
    * libterm-progressbar-perl
    * liblog-log4perl-perl
    * libjson-parse-perl
    * libjson-perl
    * libjson-validator-perl
    * libtest-simple-perl
    * libxml-libxml-perl
    * libamazon-s3-perl

## Installation

`perl Makefile.PL INSTALL_BASE=/usr/local VERSION=0.0.1`

## Utilisation en submodule GIT

* Si le dépôt de code est à côté : `git submodule add ../core-perl.git core`
* Sinon : `git submodule add https://github.com/rok4/core-perl.git core`

## Variables d'environnement utilisées dans les librairies

Leur définition est contrôlée à l'usage.

* `ROK4_TMS_DIRECTORY` pour y chercher les Tile Matrix Sets
* Pour le stockage CEPH
    - `ROK4_CEPH_CONFFILE`
    - `ROK4_CEPH_USERNAME`
    - `ROK4_CEPH_CLUSTERNAME`
* Pour le stockage S3
    - `ROK4_S3_URL`
    - `ROK4_S3_KEY`
    - `ROK4_S3_SECRETKEY`
* Pour le stockage SWIFT
    - `ROK4_SWIFT_AUTHURL`
    - `ROK4_SWIFT_USER`
    - `ROK4_SWIFT_PASSWD`
    - `ROK4_SWIFT_PUBLICURL`
    - Si authentification via Swift
        - `ROK4_SWIFT_ACCOUNT`
    - Si connection via keystone (présence de `ROK4_KEYSTONE_DOMAINID`)
        - `ROK4_KEYSTONE_DOMAINID`
        - `ROK4_KEYSTONE_PROJECTID`
* Pour configurer l'agent de requête (intéraction SWIFT et S3)
    - `ROK4_SSL_NO_VERIFY`
    - `HTTP_PROXY`
    - `HTTPS_PROXY`
    - `NO_PROXY`