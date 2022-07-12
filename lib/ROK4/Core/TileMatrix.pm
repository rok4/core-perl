# Copyright © (2011) Institut national de l'information
#                    géographique et forestière 
# 
# Géoportail SAV <contact.geoservices@ign.fr>
# 
# This software is a computer program whose purpose is to publish geographic
# data using OGC WMS and WMTS protocol.
# 
# This software is governed by the CeCILL-C license under French law and
# abiding by the rules of distribution of free software.  You can  use, 
# modify and/ or redistribute the software under the terms of the CeCILL-C
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info". 
# 
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability. 
# 
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or 
# data to be ensured and,  more generally, to use and operate it in the 
# same conditions as regards security.
# 
# The fact that you are presently reading this means that you have had
# 
# knowledge of the CeCILL-C license and that you accept its terms.

################################################################################

=begin nd
File: TileMatrix.pm

Class: ROK4::Core::TileMatrix

(see libperlauto/ROK4_Core_TileMatrix.png)

A Tile Matrix defines a grid for a level. Informations are extracted from a XML file.

Using:
    (start code)
    use ROK4::Core::TileMatrix;

    my $params = {
        id             => "18",
        resolution     => 0.5,
        topLeftCornerX => 0,
        topLeftCornerY => 12000000,
        tileWidth      => 256,
        tileHeight     => 256,
        matrixWidth    => 10080,
        matrixHeight   => 84081,
    };

    my $objTM = ROK4::Core::TileMatrix->new($params);                # ie '/home/ign/tms/'
    (end code)

Attributes:
    id - string - TM identifiant (no underscore).
    tms - <ROK4::Core::TileMatrixSet> - TMS to whom it belong
    resolution - double - Ground size of a pixel, using unity of the SRS.
    topLeftCornerX - double - X coordinate of the upper left corner for the level, the grid's origin.
    topLeftCornerY - double - Y coordinate of the upper left corner for the level, the grid's origin.
    tileWidth - integer - Pixel width of a tile.
    tileHeight - integer -  Pixel height of a tile.
    matrixWidth - integer - Number of tile in the grid, widthwise.
    matrixHeight - integer -  Number of tile in the grid, heightwise.
    targetsTm - <ROK4::Core::TileMatrix> array - Determine other levels which use this one to be generated. Empty if this level belong to a quad tree <TileMatrixSet>.

Limits:
    Resolution have to be the same  X and Y wise.
=cut

################################################################################

package ROK4::Core::TileMatrix;

use strict;
use warnings;

use Math::BigFloat;
use Log::Log4perl qw(:easy);
use List::Util qw(min max);

use ROK4::Core::ProxyGDAL;


################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

################################################################################

BEGIN {}
INIT {}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

TileMatrix constructor. Bless an instance.

Parameters (hash):
    id - string - Level identifiant
    resolution - double - X and Y wise resolution
    topLeftCornerX - double - Origin easting
    topLeftCornerY - double - Origin northing
    tileWidth - integer -  Tile width, in pixel
    tileHeight - integer - Tile height, in pixel
    matrixWidth - integer - Grid width, in tile
    matrixHeight - integer - Grid height, in tile

See also:
    <_init>
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        id             => undef,
        tms            => undef,
        resolution     => undef,
        topLeftCornerX => undef,
        topLeftCornerY => undef,
        tileWidth      => undef,
        tileHeight     => undef,
        matrixWidth    => undef,
        matrixHeight   => undef,
        targetsTm   => [],
    };

    bless($this, $class);


    # init. class
    if (! $this->_init($params)) {
        return undef;
    }

    return $this;
}

=begin nd
Function: _init

Check and store TileMatrix's informations.

Parameters (hash):
    id - string - Level identifiant
    resolution - double - X and Y wise resolution
    topLeftCornerX - double - Origin easting
    topLeftCornerY - double - Origin northing
    tileWidth - integer -  Tile width, in pixel
    tileHeight - integer - Tile height, in pixel
    matrixWidth - integer - Grid width, in tile
    matrixHeight - integer - Grid height, in tile
=cut
sub _init {
    my $this   = shift;
    my $params = shift;

    return FALSE if (! defined $params);
    
    # parameters mandatory !       
    if (! exists($params->{id}) || ! defined ($params->{id})) {ERROR("'id' information missing"); return FALSE;}
    if (! exists($params->{resolution}) || ! defined ($params->{resolution})) {ERROR("'resolution' information missing"); return FALSE;}
    if (! exists($params->{topLeftCornerX}) || ! defined ($params->{topLeftCornerX})) {ERROR("'topLeftCornerX' information missing"); return FALSE;}
    if (! exists($params->{topLeftCornerY}) || ! defined ($params->{topLeftCornerY})) {ERROR("'topLeftCornerY' information missing"); return FALSE;}
    if (! exists($params->{tileWidth}) || ! defined ($params->{tileWidth})) {ERROR("'tileWidth' information missing"); return FALSE;}
    if (! exists($params->{tileHeight}) || ! defined ($params->{tileHeight})) {ERROR("'tileHeight' information missing"); return FALSE;}
    if (! exists($params->{matrixWidth}) || ! defined ($params->{matrixWidth})) {ERROR("'matrixWidth' information missing"); return FALSE;}
    if (! exists($params->{matrixHeight}) || ! defined ($params->{matrixHeight})) {ERROR("'matrixHeight' information missing"); return FALSE;}
    
    # init. params
    $this->{id} = $params->{id};
    if ($this->{id} =~ m/_/) {
        ERROR("A TMS level id have not to contain an underscore");
        return FALSE;
    }


    $this->{resolution} = $params->{resolution};
    $this->{topLeftCornerX} = $params->{topLeftCornerX};
    $this->{topLeftCornerY} = $params->{topLeftCornerY};
    $this->{tileWidth} = $params->{tileWidth};
    $this->{tileHeight} = $params->{tileHeight};
    $this->{matrixWidth} = $params->{matrixWidth};
    $this->{matrixHeight} = $params->{matrixHeight};

    return TRUE;
}

####################################################################################################
#                                   Group: Coordinates manimulators                                #
####################################################################################################


=begin nd
Function: columnToX

Returns the X coordinate, in the TMS SRS, of the upper left corner, from the column indice and the number of tiles per width.

Parameters (list):
    col - integer - Column indice
    tilesPerWidth - integer - Optionnal (1 if undefined) 
=cut
sub columnToX {
    my $this  = shift;
    my $col   = shift;
    my $tilesPerWidth = shift;
    
    $tilesPerWidth = 1 if (! defined $tilesPerWidth);
    
    my $xo  = $this->getTopLeftCornerX;
    my $rx  = Math::BigFloat->new($this->getResolution);
    my $width = $this->getTileWidth;
    
    my $x = $xo + $col * $rx * $width * $tilesPerWidth;
    
    return $x;
}

=begin nd
Function: rowToY

Returns the Y coordinate, in the TMS SRS, of the upper left corner, from the row indice and the number of tiles per height.

Parameters (list):
    row - integer - Row indice
    tilesPerHeight - integer - Optionnal (1 if undefined)
=cut
sub rowToY {
    my $this  = shift;
    my $row   = shift;
    my $tilesPerHeight = shift;
    
    $tilesPerHeight = 1 if (! defined $tilesPerHeight);
    
    my $yo = $this->getTopLeftCornerY;
    my $ry = Math::BigFloat->new($this->getResolution);
    my $height = $this->getTileHeight;
    
    my $y = $yo - ($row * $ry * $height * $tilesPerHeight);
    
    return $y;
}

=begin nd
Function: xToColumn

Returns the column indice for the given X coordinate and the number of tiles per width.

Parameters (list):
    x - double - x-axis coordinate
    tilesPerWidth - integer - Optionnal (1 if undefined) 
=cut
sub xToColumn {
    my $this  = shift;
    my $x     = shift;
    my $tilesPerWidth = shift;
    
    $tilesPerWidth = 1 if (! defined $tilesPerWidth);
    
    my $xo  = $this->getTopLeftCornerX;
    my $rx  = Math::BigFloat->new($this->getResolution);
    my $width = $this->getTileWidth;
    
    my $col = int(($x - $xo) / ($rx * $width * $tilesPerWidth)) ;
    
    return $col->numify();
}

#
=begin nd
Function: yToRow

Returns the row indice for the given Y coordinate and the number of tiles per height.

Parameters (list):
    y - double - y-axis coordinate
    tilesPerHeight - integer - Optionnal (1 if undefined) 
=cut
sub yToRow {
    my $this  = shift;
    my $y     = shift;
    my $tilesPerHeight = shift;
    
    $tilesPerHeight = 1 if (! defined $tilesPerHeight);
    
    my $yo  = $this->getTopLeftCornerY;
    my $ry  = Math::BigFloat->new($this->getResolution);
    my $height = $this->getTileHeight;
    
    my $row = int(($yo - $y) / ($ry * $height * $tilesPerHeight)) ;
    
    return $row->numify();
}

#
=begin nd
Function: indicesToBbox

Returns the BBox from image's indices in a list : (xMin,yMin,xMax,yMax).

Parameters (list):
    col - integer - Image's column
    row - integer - Image's row
    tilesPerWidth - integer - Number of tile in the image, widthwise
    tilesPerHeight - integer - Number of tile in the image, heightwise
    crop - boolean - Default false, limit tiles indices to tile matrix limits
=cut
sub indicesToBbox {
    my $this = shift;
    my $col = shift;
    my $row = shift;
    my $tilesPerWidth = shift;
    my $tilesPerHeight = shift;
    my $crop = shift;

    

    # Calcul des tuiles extrêmes
    my $colMin = $col * $tilesPerWidth;
    my $rowMin = $row * $tilesPerHeight;

    my $colMax = $colMin + $tilesPerWidth;
    my $rowMax = $rowMin + $tilesPerHeight;

    if (defined $crop && $crop) {
        $colMin = max ($colMin, 0);
        $rowMin = max ($rowMin, 0);
        $colMax = min ($colMax, $this->{matrixWidth});
        $rowMax = min ($rowMax, $this->{matrixHeight});
    }

    my $res = Math::BigFloat->new($this->{resolution});    
    
    my $xMin = $this->{topLeftCornerX} + $res * $colMin * $this->{tileWidth};
    my $yMin = $this->{topLeftCornerY} - $res * $rowMax * $this->{tileHeight};
    my $xMax = $this->{topLeftCornerX} + $res * $colMax * $this->{tileWidth};
    my $yMax = $this->{topLeftCornerY} - $res * $rowMin * $this->{tileHeight};
    
    return ($xMin,$yMin,$xMax,$yMax);
}

#
=begin nd
Function: indicesToGeom

Returns the OGR Geometry from slab's indices.

Parameters (list):
    col - integer - Image's column
    row - integer - Image's row
    tilesPerWidth - integer - Number of tile in the image, widthwise
    tilesPerHeight - integer - Number of tile in the image, heightwise
=cut
sub indicesToGeom {
    my $this  = shift;
    my $col     = shift;
    my $row     = shift;
    my $tilesPerWidth = shift;
    my $tilesPerHeight = shift;
    
    my ($xMin,$yMin,$xMax,$yMax) = $this->indicesToBbox($col, $row, $tilesPerWidth, $tilesPerHeight);
    
    return ROK4::Core::ProxyGDAL::geometryFromBbox($xMin,$yMin,$xMax,$yMax);
}

#
=begin nd
Function: indicesToTFW

Returns the TFW from image's indices.

Parameters (list):
    col - integer - Image's column
    row - integer - Image's row
    tilesPerWidth - integer - Number of tile in the image, widthwise
    tilesPerHeight - integer - Number of tile in the image, heightwise
=cut
sub indicesToTFW {
    my $this  = shift;
    my $col     = shift;
    my $row     = shift;
    my $tilesPerWidth = shift;
    my $tilesPerHeight = shift;
    
    my $imgGroundWidth = $this->getImgGroundWidth($tilesPerWidth);
    my $imgGroundHeight = $this->getImgGroundHeight($tilesPerHeight);

    my $tfwText = "";

    $tfwText .= sprintf "%s\n", $this->{resolution};
    $tfwText .= "0\n";
    $tfwText .= "0\n";
    $tfwText .= sprintf "%s\n", -1 * $this->{resolution};
    $tfwText .= sprintf "%s\n", $this->{topLeftCornerX} + $this->{resolution} * $tilesPerWidth * $this->{tileWidth} * $col + 0.5 * $this->{resolution};
    $tfwText .= sprintf "%s", $this->{topLeftCornerY} - $this->{resolution} * $tilesPerHeight * $this->{tileHeight} * $row - 0.5 * $this->{resolution};

    return $tfwText;
}


=begin nd
Function: bboxToIndices

Returns the extrem indices from a bbox in a list : ($rowMin, $rowMax, $colMin, $colMax).

Parameters (list):
    xMin,yMin,xMax,yMax - bounding box
    tilesPerWidth - integer - Number of tile in the slab, widthwise
    tilesPerHeight - integer - Number of tile in the slab, heightwise
=cut
sub bboxToIndices {
    my $this = shift;
    
    my $xMin = shift;
    my $yMin = shift;
    my $xMax = shift;
    my $yMax = shift;
    my $tilesPerWidth = shift;
    my $tilesPerHeight = shift;
    
    my $rowMin = $this->yToRow($yMax,$tilesPerHeight);
    my $rowMax = $this->yToRow($yMin,$tilesPerHeight);
    my $colMin = $this->xToColumn($xMin,$tilesPerWidth);
    my $colMax = $this->xToColumn($xMax,$tilesPerWidth);
    
    return ($rowMin, $rowMax, $colMin, $colMax);
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getID
sub getID {
    my $this = shift;
    return $this->{id}; 
}

# Function: getOrder
sub getOrder {
    my $this = shift;
    return $this->{tms}->getOrderfromID($this->{id});
}

# Function: setTMS
sub setTMS {
    my $this = shift;
    my $tms = shift;
    
    if ( ! defined ($tms) || ref ($tms) ne "ROK4::Core::TileMatrixSet" ) {
        ERROR("We expect to a ROK4::Core::TileMatrixSet object.");
    } else {
        $this->{tms} = $tms;
    }
}    

# Function: getResolution
sub getResolution {
    my $this = shift;
    return $this->{resolution}; 
}

# Function: getTileWidth
sub getTileWidth {
    my $this = shift;
    return $this->{tileWidth}; 
}

# Function: getTileHeight
sub getTileHeight {
    my $this = shift;
    return $this->{tileHeight}; 
}

# Function: getMatrixWidth
sub getMatrixWidth {
    my $this = shift;
    return $this->{matrixWidth}; 
}

# Function: getMatrixHeight
sub getMatrixHeight {
    my $this = shift;
    return $this->{matrixHeight}; 
}

# Function: getTopLeftCornerX
sub getTopLeftCornerX {
    my $this = shift;
    return Math::BigFloat->new($this->{topLeftCornerX}); 
}

# Function: getTopLeftCornerY
sub getTopLeftCornerY {
    my $this = shift;
    return Math::BigFloat->new($this->{topLeftCornerY}); 
}

# Function: getTargetsTm
sub getTargetsTm {
    my $this = shift;
    return $this->{targetsTm}
}

# Function: getSRS
sub getSRS {
    my $this = shift;
    return $this->{tms}->getSRS();
}

=begin nd
Function: addTargetTm

Parameters (list):
    tm - <TileMatrix> - Tile Matrix to add to target ones
=cut
sub addTargetTm {
    my $this = shift;
    my $tm = shift;
    push @{$this->{targetsTm}}, $tm;
}

1;
__END__
