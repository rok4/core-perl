# Librairies ROK4 core Perl

## Summary

Le projet ROK4 a été totalement refondu, dans son organisation et sa mise à disposition. Les composants sont désormais disponibles dans des releases sur GitHub au format debian.

Cette release contient les librairies Perl, utilisées par les outils de [prégénération](https://github.com/rok4/pregeneration) et ceux de [gestion et analyse](https://github.com/rok4/tools).

## Changelog

### [Added]

* Ajout de fonction de clonage des pyramides et niveaux pour faciliter 
* Possibilité de faire des liens symboliques inter contenant sur les stockages objets
* Nouvelle classe GeoVector, pour gérer les fichiers vecteur en source des générations de pyramide de tuiles vectorielles

### [Changed]

* Passage à la librairie Net::Amazon::S3 pour les intéractions avec le stockage S3
* Réorganisation de l'agencement des pyramides sur le stockage
* Uniformisation des noms des formats de pyramide
* Les descripteurs de pyramides et de couches sont au format JSON

### [Removed]

* Suppression de la classe de pyramide raster à la demande
* Suppression de la classe dédiée au spécifications raster (utilisation directe de la classe Pixel)

<!-- 
### [Added]

### [Changed]

### [Deprecated]

### [Removed]

### [Fixed]

### [Security] 
-->