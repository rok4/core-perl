## 2.0.0

### [Fixed]

* `Database` : lorsque qu'un attribut dont on veut les valeurs min et max correspond à du vocabulaire SQL, il faut le mettre entre double quote.

### [Changed]

* `Pixel` : refonte de la syntaxe des formats (sampleformat contient le nombre de bits : uint8 et float32)
* `PyramidRaster` : on ne valide la valeur de nodata que si il n'y a pas de style (qui vient modifier les caractéristiques raster)

## 1.1.1

### [Fixed]

* `Database` : lorsque qu'un attribut dont on veut les valeurs distinctes correspond à du vocabulaire SQL, il faut le mettre entre double quote.
* `TileMatrixSet` : pour chercher le niveau dont la résolution est la plus proche de celle fournie, on accepte des ratios entre 0.8 et 1.6 pour toujours avoir une solution avec les TMS quadtree

## 1.1.0

### [Fixed]

* Indentification de la compression dans les formats "RAW"

### [Added]

* Possibilité de préciser une région S3 et si on souhaite utiliser des hôtes virtuels (bucket en sous domaine)

<!-- 
### [Added]

### [Changed]

### [Deprecated]

### [Removed]

### [Fixed]

### [Security] 
-->