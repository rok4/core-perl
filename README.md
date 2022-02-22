# Librairies CORE Perl

- [Dépendances](#dépendances)
- [Installation](#installation)
- [Utilisation en submodule GIT](#utilisation-en-submodule-git)

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
    * libtest-simple-perl
    * libxml-libxml-perl
    * libamazon-s3-perl

## Installation

`perl Makefile.PL INSTALL_BASE=/usr/local VERSION=0.0.1`

## Utilisation en submodule GIT

* Si le dépôt de code est à côté : `git submodule add ../core-perl.git core`
* Sinon : `git submodule add https://github.com/rok4/core-perl.git core`