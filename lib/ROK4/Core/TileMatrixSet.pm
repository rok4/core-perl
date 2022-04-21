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
File: TileMatrixSet.pm

Class: ROK4::Core::TileMatrixSet

(see libperlauto/Core_TileMatrixSet.png)

Load and store all information about a Tile Matrix Set. A Tile Matrix Set is a JSON file which describe a grid for several levels.

The file have to be in the directory provided with the environment variable ROK4_TMS_DIRECTORY

(see ROK4GENERATION/TileMatrixSet.png)

We tell the difference between :
    - quad tree TMS : resolutions go by tows and borders are aligned. To generate a pyramid which is based on this kind of TMS, we use <QTree>
    (see ROK4GENERATION/QTreeTMS.png)
    - "nearest neighbour" TMS : centers are aligned (used for DTM generations, with a "nearest neighbour" interpolation). To generate a pyramid which is based on this kind of TMS, we use <Graph>
    (see ROK4GENERATION/NNGraphTMS.png)

Using:
    (start code)
    use ROK4::Core::TileMatrixSet;

    my $tms_name = "LAMB93_50cm.json";
    my $objTMS = ROK4::Core::TileMatrixSet->new($tms_name);

    $objTMS->getTileMatrixCount()};      # ie 19
    $objTMS->getTileMatrix(12);          # object TileMatrix with level id = 12
    $objTMS->getSRS();                   # ie 'IGNF:LAMB93'
    $objTMS->getName();                  # ie 'LAMB93_50cm'
    $objTMS->getFile();                  # ie 'LAMB93_50cm.json'
    (end code)

Attributes:
    PATHFILENAME - string - Complete file path : /path/to/SRS_RES.json
    name - string - Basename part of PATHFILENAME : SRS_RES
    filename - string - Filename part of PATHFILENAME : SRS_RES.json

    levelsBind - hash - Link between Tile matrix identifiants (string, the key) and order in ascending resolutions (integer, the value).
    topID - string - Higher level ID.
    topResolution - double - Higher level resolution.
    bottomID - string - Lower level ID.
    bottomResolution - double - Lower level resolution.

    srs - string - Spatial Reference System, casted in uppercase (EPSG:4326).
    coordinatesInversion - boolean - Precise if we have to reverse coordinates to harvest in this SRS. For some SRS, we have to reverse coordinates when we compose WMS request (1.3.0). Used test to determine this SRSs is : if the SRS is geographic and an EPSG one.
    tileMatrix - <ROK4::Core::TileMatrix> hash - Keys are Tile Matrix identifiant, values are <TileMatrix> objects.
    type - string - Type of TMS, QTREE or NNGRAPH

Limitations:
    File name of tms must be with extension : tms or TMS.

    All levels must be continuous (QuadTree) and unique.

=cut

################################################################################

package ROK4::Core::TileMatrixSet;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use JSON::Parse qw(assert_valid_json parse_json);

use Data::Dumper;

use ROK4::Core::TileMatrix;
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

TileMatrixSet constructor. Bless an instance. Fill file's informations.

Parameters (list):
    tms_name - string - Name of the Tile Matrix File, with extension JSON or TMS or without
    acceptUntypedTMS - boolean - optional : Do we accept a TMS that is neither a quad tree nor a neares neighbour graph (default : refused)

See also:
    <_load>
=cut
sub new {
    my $class = shift;
    my $tms_name = shift;
    my $acceptUntypedTMS = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        PATHFILENAME => undef,
        name     => undef,
        filename => undef,
        #
        levelsBind => undef,
        topID => undef,
        topResolution => undef,
        bottomID => undef,
        bottomResolution  => undef,
        #
        srs        => undef,
        coordinatesInversion  => FALSE,
        tileMatrix => {},
        #
        type => undef
    };

    bless($this, $class);

    return undef if (! defined $tms_name);

    if ($tms_name !~ m/\.(tms|TMS|json|JSON)$/) {
        $tms_name = "$tms_name.json";
    }

    if (! defined $ENV{ROK4_TMS_DIRECTORY}) {
        ERROR ("Environment variable ROK4_TMS_DIRECTORY is not defined, cannot load TMS");
        return undef;
    }

    $this->{filename} = $tms_name;

    $this->{name} = $tms_name;
    $this->{name} =~ s/\.(tms|TMS|json|JSON)$//;

    $this->{PATHFILENAME} = File::Spec->catfile($ENV{ROK4_TMS_DIRECTORY}, $this->{filename});

    if (! -f $this->{PATHFILENAME}) {
        ERROR(sprintf "File TMS doesn't exist (%s)!", $this->{PATHFILENAME});
        return undef;
    }
    
    # load
    return undef if (! $this->_load($acceptUntypedTMS));

    return $this;
}

=begin nd
Function: _load

Read and parse the Tile Matrix Set JSON file to create a TileMatrix object for each level.

It determines if the TMS match with a quad tree:
    - resolutions go by twos between two contigues levels
    - top left corner coordinates and pixel dimensions are same for all levels

If TMS is a nearest neighbour graph, we have to determine the lower source level for each level (used for the generation).

Parameters (list):
    acceptUntypedTMS - boolean - optional : Do we accept a TMS that is neither a quad tree nor a neares neighbour graph (default : refused)

See also:
    <computeTmSource>
=cut
sub _load {
    my $this = shift;
    my $acceptUntypedTMS = shift;
    
    my $json_text = do {
        open(my $json_fh, "<", $this->{PATHFILENAME}) or do {
            ERROR(sprintf "Cannot open JSON file : %s (%s)", $this->{PATHFILENAME}, $! );
            return FALSE;
        };
        local $/;
        <$json_fh>
    };

    eval { assert_valid_json ($json_text); };
    if ($@) {
        ERROR(sprintf "File %s is not a valid JSON", $this->{PATHFILENAME});
        ERROR($@);
        return FALSE;
    }

    my $tms_json_object = parse_json ($json_text);
  
    # load tileMatrix
    foreach my $tm (@{$tms_json_object->{tileMatrices}}) {
        # we identify level max (with the best resolution, the smallest) and level min (with the 
        # worst resolution, the biggest)
        my $id = $tm->{id};
        my $res = $tm->{cellSize};
        
        if (! defined $this->{topID} || $res > $this->{topResolution}) {
            $this->{topID} = $id;
            $this->{topResolution} = $res;
        }
        if (! defined $this->{bottomID} || $res < $this->{bottomResolution}) {
            $this->{bottomID} = $id;
            $this->{bottomResolution} = $res;
        }
        
        my $objTM = ROK4::Core::TileMatrix->new({
            id => $id,
            resolution     => $res,
            topLeftCornerX => $tm->{pointOfOrigin}->[0],
            topLeftCornerY => $tm->{pointOfOrigin}->[1],
            tileWidth      => $tm->{tileWidth},
            tileHeight     => $tm->{tileHeight},
            matrixWidth    => $tm->{matrixWidth},
            matrixHeight   => $tm->{matrixHeight},
        });
        
        if (! defined $objTM) {
            ERROR(sprintf "Cannot create the TileMatrix object for the level '%s'",$id);
            return FALSE;
        }
        
        $this->{tileMatrix}->{$id} = $objTM;
        $objTM->setTMS($this);
        undef $objTM;
    }
    
    if (! $this->getCountTileMatrix()) {
        ERROR (sprintf "No tile matrix loading from JSON file TMS !");
        return FALSE;
    }
    
    # srs (== crs)
    if (! exists $tms_json_object->{crs}) {
        ERROR (sprintf "Can not determine parameter 'crs' in the JSON file TMS !");
        return FALSE;
    }
    $this->{srs} = uc($tms_json_object->{crs}); # srs is cast in uppercase in order to ease comparisons
    
    # Have coodinates to be reversed ?
    my $sr = ROK4::Core::ProxyGDAL::spatialReferenceFromSRS($this->{srs});
    if (! defined $sr) {
        ERROR (sprintf "Impossible to initialize the final spatial coordinate system (%s) to know if coordinates have to be reversed !\n",$this->{srs});
        return FALSE;
    }

    my $authority = (split(":",$this->{srs}))[0];
    if (ROK4::Core::ProxyGDAL::isGeographic($sr) && uc($authority) eq "EPSG") {
        DEBUG(sprintf "Coordinates will be reversed in requests (SRS : %s)",$this->{srs});
        $this->{coordinatesInversion} = TRUE;
    } else {
        DEBUG(sprintf "Coordinates order will be kept in requests (SRS : %s)",$this->{srs});
        $this->{coordinatesInversion} = FALSE;
    }
        
    # tileMatrix list sort by resolution
    my @tmList = $this->getTileMatrixByArray();
        
    # Is TMS a QuadTree ? If not, we use a graph (less efficient for calculs)
    $this->{type} = "QTREE"; # default value
    if (scalar(@tmList) != 1) {
        my $epsilon = $tmList[0]->getResolution / 100 ;
        for (my $i = 0; $i < scalar(@tmList) - 1;$i++) {
            if ( abs($tmList[$i]->getResolution*2 - $tmList[$i+1]->getResolution) > $epsilon ) {
                $this->{type} = "NONE";
                INFO(sprintf "Not a QTree : resolutions don't go by twos : level '%s' (%s) and level '%s' (%s).",
                    $tmList[$i]->{id},$tmList[$i]->getResolution,
                    $tmList[$i+1]->{id},$tmList[$i+1]->getResolution);
                last;
            }
            elsif ( abs($tmList[$i]->getTopLeftCornerX - $tmList[$i+1]->getTopLeftCornerX) > $epsilon ) {
                $this->{type} = "NONE";
                ERROR(sprintf "Not a QTree : 'topleftcornerx' is not the same for all levels : level '%s' (%s) and level '%s' (%s).",
                    $tmList[$i]->{id},$tmList[$i]->getTopLeftCornerX,
                    $tmList[$i+1]->{id},$tmList[$i+1]->getTopLeftCornerX);
                last;
            }
            elsif ( abs($tmList[$i]->getTopLeftCornerY - $tmList[$i+1]->getTopLeftCornerY) > $epsilon ) {
                $this->{type} = "NONE";
                ERROR(sprintf "Not a QTree : 'topleftcornery' is not the same for all levels : level '%s' (%s) and level '%s' (%s).",
                    $tmList[$i]->{id},$tmList[$i]->getTopLeftCornerY,
                    $tmList[$i+1]->{id},$tmList[$i+1]->getTopLeftCornerY);
                last;
            }
            elsif ( $tmList[$i]->getTileWidth != $tmList[$i+1]->getTileWidth) {
                $this->{type} = "NONE";
                ERROR(sprintf "Not a QTree : 'tilewidth' is not the same for all levels : level '%s' (%s) and level '%s' (%s).",
                    $tmList[$i]->{id},$tmList[$i]->getTileWidth,
                    $tmList[$i+1]->{id},$tmList[$i+1]->getTileWidth);
                last;
            }
            elsif ( $tmList[$i]->getTileHeight != $tmList[$i+1]->getTileHeight) {
                $this->{type} = "NONE";
                INFO(sprintf "Not a QTree : 'tileheight' is not the same for all levels : level '%s' (%s) and level '%s' (%s).",
                    $tmList[$i]->{id},$tmList[$i]->getTileHeight,
                    $tmList[$i+1]->{id},$tmList[$i+1]->getTileHeight);
                last;
            }
        };
    };
  
    # on fait un hash pour retrouver l'ordre d'un niveau a partir de son id.
    for (my $i=0; $i < scalar @tmList; $i++){
        $this->{levelsBind}{$tmList[$i]->getID()} = $i;
    }
    


    if ($this->{type} eq "QTREE") { return TRUE;}
    
    ## Adding informations about child/parent in TM objects
    for (my $i = 0; $i < scalar(@tmList) ;$i++) {
        if (! $this->computeTmSource($tmList[$i])) {
            if(defined $acceptUntypedTMS && $acceptUntypedTMS) {
                return TRUE;
            } else {
                ERROR(sprintf "Nor a QTree neither a Graph made for nearest neighbour generation. No source for level %s.",$tmList[$i]->getID());
                return FALSE;
            }
        }
    }

    $this->{type} = "NNGRAPH";
    
    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

# Function: getPathFilename
sub getPathFilename {
    my $this = shift;
    return $this->{PATHFILENAME};
}

# Function: getSRS
sub getSRS {
  my $this = shift;
  return $this->{srs};
}

# Function: getInversion
sub getInversion {
  my $this = shift;
  return $this->{coordinatesInversion};
}

# Function: getName
sub getName {
  my $this = shift;
  return $this->{name};
}

# Function: getPath
sub getPath {
  my $this = shift;
  return $this->{filepath};
}

# Function: getFile
sub getFile {
  my $this = shift;
  return $this->{filename};
}

# Function: getTopLevel
sub getTopLevel {
  my $this = shift;
  return $this->{topID};
}

# Function: getBottomLevel
sub getBottomLevel {
  my $this = shift;
  return $this->{bottomID};
}

# Function: getTopResolution
sub getTopResolution {
  my $this = shift;
  return $this->{topResolution};
}

# Function: getBottomResolution
sub getBottomResolution {
  my $this = shift;
  return $this->{bottomResolution};
}

=begin nd
Function: getTileWidth

Parameters (list):
    ID - string - Level identifiant whose tile pixel width we want.
=cut
sub getTileWidth {
  my $this = shift;
  my $levelID = shift;
  
  $levelID = $this->{bottomID} if (! defined $levelID);
  
  # size of tile in pixel !
  return $this->{tileMatrix}->{$levelID}->getTileWidth;
}

=begin nd
Function: getTileHeight

Parameters (list):
    ID - string - Level identifiant whose tile pixel height we want.
=cut
sub getTileHeight {
  my $this = shift;
  my $ID = shift;
  
  $ID = $this->{bottomID} if (! defined $ID);
  
  # size of tile in pixel !
  return $this->{tileMatrix}->{$ID}->getTileHeight;
}

# Function: isQTree
sub isQTree {
    my $this = shift;
    return ($this->{type} eq "QTREE");
}

=begin nd
Function: getTileMatrixByArray

Returns the tile matrix array in the ascending resolution order.

Parameters (list):
    fromLevelID - string - Optionnal, level ID from which we return levels.
    toLevelID - string - Optionnal, level ID to which we return levels.
=cut
sub getTileMatrixByArray {
    my $this = shift;
    my $fromLevelID = shift;
    my $toLevelID = shift;

    if (! defined $fromLevelID || ! exists $this->{tileMatrix}->{$fromLevelID}) {
        $fromLevelID = $this->{bottomID};
    }

    if (! defined $toLevelID || ! exists $this->{tileMatrix}->{$toLevelID}) {
        $toLevelID = $this->{topID};
    }

    my @levels;

    my $add = FALSE;
    foreach my $k (sort {$a->getResolution() <=> $b->getResolution()} (values %{$this->{tileMatrix}})) {
        if (! $add && $k->getID() ne "$fromLevelID") {
            next;
        }
        $add = TRUE;
        push @levels, $k;
        if ($k->getID() eq "$toLevelID") {
            last;
        }
    }

    return @levels;
}

=begin nd
Function: getTileMatrix

Returns the tile matrix from the supplied ID. This ID is the TMS ID (string) and not the ascending resolution order (integer). Returns undef if ID is undefined or if asked level doesn't exist.

Parameters (list):
    ID - string - Wanted level identifiant
=cut
sub getTileMatrix {
    my $this = shift;
    my $ID = shift;

    if (! defined $ID || ! exists($this->{tileMatrix}->{$ID})) {
        return undef;
    }

    return $this->{tileMatrix}->{$ID};
}

=begin nd
Function: getCountTileMatrix

Returns the count of tile matrix in the TMS.
=cut
sub getCountTileMatrix {
    my $this = shift;
    return scalar (keys %{$this->{tileMatrix}});
}

=begin nd
Function: getIDfromOrder

Returns the tile matrix ID from the ascending resolution order (integer).
    - 0 (bottom level, smallest resolution)
    - NumberOfTM-1 (top level, biggest resolution).

Parameters (list):
    order - integer - Level order, whose identifiant we want.
=cut
sub getIDfromOrder {
    my $this = shift;
    my $order= shift;


    foreach my $k (keys %{$this->{levelsBind}}) {
        if ($this->{levelsBind}->{$k} == $order) {return $k;}
    }

    return undef;
}

=begin nd
Function: getBelowLevelID

Returns the tile matrix ID below the given tile matrix (ID).

Parameters (list):
    ID - string - Level identifiant, whose below level ID we want.
=cut
sub getBelowLevelID {
    my $this = shift;
    my $ID= shift;

    return undef if ($ID == $this->{bottomID});

    return undef if (! exists $this->{levelsBind}->{$ID});
    my $order = $this->{levelsBind}->{$ID};
    return $this->getIDfromOrder($order-1);
}

=begin nd
Function: getAboveLevelID

Returns the tile matrix ID above the given tile matrix (ID).

Parameters (list):
    ID - string - Level identifiant, whose above level ID we want.
=cut
sub getAboveLevelID {
    my $this = shift;
    my $ID= shift;

    return undef if ($ID == $this->{topID});

    return undef if (! exists $this->{levelsBind}->{$ID});
    my $order = $this->{levelsBind}->{$ID};
    return $this->getIDfromOrder($order+1);
}

=begin nd
Function: getOrderfromID

Returns the tile matrix order from the ID.
    - 0 (bottom level, smallest resolution)
    - NumberOfTM-1 (top level, biggest resolution).

Parameters (list):
    ID - string - Level identifiant, whose order we want.
=cut
sub getOrderfromID {
    my $this = shift;
    my $ID= shift;


    if (exists $this->{levelsBind}->{$ID}) {
        return $this->{levelsBind}->{$ID};
    } else {
        return undef;
    }
}

=begin nd
Function: getBestLevelID

Returns the best level ID concording to a resolution

Parameters (list):
    objImg - <ROK4::Core::GeoImage> - Image to determine the best level from its resolutions
=cut
sub getBestLevelID {
    my $this = shift;
    my $objImg = shift;

    # On reprojete l'étendue de cette image dans la projection du TMS, pour avoir une resolution équivalente
    my $ct = ROK4::Core::ProxyGDAL::coordinateTransformationFromSpatialReference($objImg->getSRS(), $this->{srs});
    if (! defined $ct) {
        ERROR(sprintf "Cannot instanciate the coordinate transformation object %s->%s", $objImg->getSRS(), $this->{srs});
        return undef;
    }

    my @bbox = ROK4::Core::ProxyGDAL::convertBBox($ct, $objImg->getBBox()); # (xMin, yMin, xMax, yMax)
    if ($bbox[0] == 0 && $bbox[2] == 0) {
        ERROR(sprintf "Impossible to transform BBOX for the image '%s'. Probably limits are reached !", $objImg->getName());
        return undef;
    }

    my $xres = ($bbox[2] - $bbox[0]) / $objImg->getWidth();
    my $yres = ($bbox[3] - $bbox[1]) / $objImg->getHeight();
    my $res = sqrt($xres * $yres);

    my $best_ratio = undef;
    my $best_level = undef;
    # On cherche le niveau avec un ratio le plus proche de 1, ne sortant pas de [0.8, 1.5]
    while (my ($level, $tm) = each(%{$this->{tileMatrix}})) {
        my $ratio = $res / $tm->getResolution();
        if ($ratio < 0.8 || $ratio > 1.5) {
            next;
        }
        if (! defined $best_ratio || abs($ratio - 1) < abs($best_ratio - 1)) {
            $best_ratio = $ratio;
            $best_level = $level;
        }
    }

    INFO("Best level found : $best_level (ratio $best_ratio)");
    return $best_level;
}

####################################################################################################
#                             Group: Tile Matrix manager                                           #
####################################################################################################

=begin nd
Function: computeTmSource

Defines the tile matrix for the provided one. This method is only used for "nearest neighbour" TMS (Pixels between different level have the same centre).

Parameters (list):
    tmTarget - <TileMatrix> - Tile matrix whose source tile matrix we want to know.

Returns:
    FALSE if there is no TM source for TM target (unless TM target is BotttomTM) 
    TRUE if there is a TM source (obj) for the TM target (obj) in argument.
=cut
sub computeTmSource {
  my $this = shift;
  my $tmTarget = shift;
  
  if ($tmTarget->{id} eq $this->{bottomID}) {
    return TRUE;
  }

  # The TM to be used to compute images in TM Parent
  my $tmSource = undef;
  
  # position du pixel en haut à gauche
  my $xTopLeftCorner_CenterPixel = $tmTarget->getTopLeftCornerX() + 0.5 * $tmTarget->getResolution();
  my $yTopLeftCorner_CenterPixel = $tmTarget->getTopLeftCornerY() - 0.5 * $tmTarget->getResolution();

  for (my $i = $this->getOrderfromID($tmTarget->getID()) - 1; $i >= $this->getOrderfromID($this->getBottomLevel) ;$i--) {
      my $potentialTmSource = $this->getTileMatrix($this->getIDfromOrder($i));
      # la précision vaut 1/100 de la plus petit résolution du TMS
      my $epsilon = $this->getTileMatrix($this->getBottomLevel())->getResolution() / 100;
      my $rapport = $tmTarget->getResolution() / $potentialTmSource->getResolution() ;
      #on veut que le rapport soit (proche d') un entier
      next if ( abs( int( $rapport + 0.5) - $rapport) > $epsilon );
      # on veut que les pixels soient superposables (pour faire une interpolation nn)
      # on regarde le pixel en haut à gauche de tmtarget
      # on verfie qu'il y a bien un pixel correspondant dans tmpotentialsource
      my $potentialTm_xTopLeftCorner_CenterPixel = $potentialTmSource->getTopLeftCornerX() + 0.5 * $potentialTmSource->getResolution() ;
      next if (abs($xTopLeftCorner_CenterPixel - $potentialTm_xTopLeftCorner_CenterPixel) > $epsilon );
      my $potentialTm_yTopLeftCorner_CenterPixel = $potentialTmSource->getTopLeftCornerY() - 0.5 * $potentialTmSource->getResolution() ;
      next if (abs($yTopLeftCorner_CenterPixel - $potentialTm_yTopLeftCorner_CenterPixel) > $epsilon );
      $tmSource = $potentialTmSource;
      last;
  }
  
  # si on n'a rien trouvé, on sort en erreur
  if (!  defined $tmSource) {
     return FALSE;
  }
  
  $tmSource->addTargetTm($tmTarget);
  
  return TRUE;
}

1;
__END__


