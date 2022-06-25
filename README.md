# Librairies CORE Perl

- [Installation depuis le paquet debian](#installation-depuis-le-paquet-debian)
- [Installation depuis les sources](#installation-depuis-les-sources)
- [Variables d'environnement utilisées dans les librairies](#variables-denvironnement-utilisées-dans-les-librairies)


## Installation depuis le paquet debian

Télécharger le paquet sur GitHub : https://github.com/rok4/core-perl/releases/

```
apt install ./librok4-core-perl_<version>_all.deb
```

## Installation depuis les sources

Dépendances (paquets debian) :

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
* libnet-amazon-s3-perl

```
perl Makefile.PL INSTALL_BASE=/usr PREREQ_FATAL=1
make
make install
```

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