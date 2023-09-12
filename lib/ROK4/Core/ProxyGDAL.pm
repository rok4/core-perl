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
File: ProxyGDAL.pm

Class: ROK4::Core::ProxyGDAL

(see libperlauto/ROK4_Core_ProxyGDAL.png)

Proxy to use different versions of GDAL transparently

Using:
    (start code)
    use ROK4::Core::ProxyGDAL;
    my $geom = ROK4::Core::ProxyGDAL::geometryFromString("WKT", "POLYGON(0 0,1 0,1 1,0 1,0 0)") ;
    my $sr = ROK4::Core::ProxyGDAL::spatialReferenceFromSRS("EPSG:4326") ;
    (end code)
=cut

################################################################################

package ROK4::Core::ProxyGDAL;

use strict;
use warnings;

use Data::Dumper;
use Math::BigFloat;

use ROK4::Core::Array;


use Geo::GDAL;
use Geo::OSR;
use Geo::OGR;

use Log::Log4perl qw(:easy);

################################################################################
# Globale

my $gdalVersion = Geo::GDAL::VersionInfo();

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

my @FORMATS = ("WKT", "BBOX", "GML", "GeoJSON");

####################################################################################################
#                              Group: Geometry constructors                                        #
####################################################################################################

=begin nd
Function: geometryFromString

Return an OGR geometry from a WKT string.

Parameters (list):
    format - string - Geomtry format
    string - string - String geometry according format

Return :
    a <Geo::OGR::Geometry> object, undef if failure
=cut
sub geometryFromString {
    my $format = shift;
    my $string = shift;

    if (! defined ROK4::Core::Array::isInArray($format, @FORMATS)) {
        ERROR("Geometry string format unknown $format");
        return undef;
    }

    if ($format eq "BBOX") {
        my ($xmin,$ymin,$xmax,$ymax) = split(/,/, $string);
        return geometryFromBbox($xmin,$ymin,$xmax,$ymax);
    }
    
    my $geom;

    if ($gdalVersion =~ /^2|3/) {
        #version 2.x
        eval { $geom = Geo::OGR::Geometry->new($format => $string); };
        if ($@) {
            ERROR(sprintf "String geometry is not valid : %s \n", $@ );
            return undef;
        }
    } elsif ($gdalVersion =~ /^1/) {
        #version 1.x
        eval { $geom = Geo::OGR::Geometry->create($format => $string); };
        if ($@) {
            ERROR(sprintf "String geometry is not valid : %s \n", $@ );
            return undef;
        }
    }


    return $geom
}

=begin nd
Function: geometryFromFile

Return an OGR geometry from a file.

Parameters (list):
    file - string - File containing the geometry description

Return :
    a <Geo::OGR::Geometry> object, undef if failure
=cut
sub geometryFromFile {
    my $file = shift;

    if (! -f $file) {
        ERROR("Geometry file $file does not exist");
        return undef;
    }

    my $format;
    if ($file =~ m/\.json$/i) {
        $format = "GeoJSON";
    } elsif ($file =~ m/\.gml$/i) {
        $format = "GML";
    } else {
        $format = "WKT";
    }

    if (! open FILE, "<", $file ){
        ERROR(sprintf "Cannot open the file %s.",$file);
        return FALSE;
    }

    my $string = '';
    while( defined( my $line = <FILE> ) ) {
        $string .= $line;
    }
    close(FILE);
    
    return geometryFromString($format, $string);
}

=begin nd
Function: geometryFromBbox

Return the OGR Geometry from a bbox

Parameters (list):
    xmin - float
    ymin - float
    xmax - float
    ymax - float

Return (list):
    a <Geo::OGR::Geometry> object, undef if failure
=cut
sub geometryFromBbox {
    my ($xmin,$ymin,$xmax,$ymax) = @_;

    if ($xmax <= $xmin || $ymax <= $ymin) {
        ERROR("Coordinates are not logical for a bbox (max < min) : $xmin,$ymin $xmax,$ymax");
        return undef ;
    }

    my @points;

    my $x_step = ($xmax - $xmin) / 10;
    my $y_step = ($ymax - $ymin) / 10;

    for (my $i = 0; $i < 10; $i++) {push(@points, sprintf("%s $ymin", $xmin + $x_step * $i));}
    for (my $i = 0; $i < 10; $i++) {push(@points, sprintf("$xmax %s", $ymin + $y_step * $i));}
    for (my $i = 0; $i < 10; $i++) {push(@points, sprintf("%s $ymax", $xmax - $x_step * $i));}
    for (my $i = 0; $i < 10; $i++) {push(@points, sprintf("$xmin %s", $ymax - $y_step * $i));}
    push(@points, "$xmin $ymin");

    my $wkt = sprintf "POLYGON((%s))", join(",", @points);
    return geometryFromString("WKT", $wkt);
}


####################################################################################################
#                               Group: Geometry tools                                              #
####################################################################################################


=begin nd
Function: getBbox

Return the bbox from a OGR geometry object

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    (xmin,ymin,xmax,ymax), xmin is undefined if failure
=cut
sub getBbox {
    my $geom = shift;

    my $bboxref = $geom->GetEnvelope();

    return ($bboxref->[0],$bboxref->[2],$bboxref->[1],$bboxref->[3]);
}

=begin nd
Function: getBboxes

Return the bboxes from a OGR geometry object. If geometry is a collection, we have one bbox per geometry in the collection.

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (Array reference of array references):
    Array reference of N (xmin,ymin,xmax,ymax), undef if failure
=cut
sub getBboxes {
    my $geom = shift;

    my $bboxes = [];

    my $count = $geom->GetGeometryCount();

    for (my $i = 0; $i < $count ; $i++) {
        my $part = $geom->GetGeometryRef($i);
        my $bboxpart = $part->GetEnvelope();

        push @{$bboxes}, [$bboxpart->[0],$bboxpart->[2],$bboxpart->[1],$bboxpart->[3]];
    }
    return $bboxes;
}

=begin nd
Function: getConvertedGeometry

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object
    ct - <Geo::OSR::CoordinateTransformation> - OGR geometry object

Return (list):
    a <Geo::OGR::Geometry> object, undefined if failure
=cut
sub getConvertedGeometry {
    my $geom = shift;
    my $ct = shift;

    my $convertExtent = $geom->Clone();
    if (defined $ct) {
        eval {
            $ENV{OGR_ENABLE_PARTIAL_REPROJECTION} = TRUE;
            $convertExtent->Transform($ct);
        };
        if ($@) { 
            ERROR(sprintf "Cannot convert geometry : %s", $@);
            return undef;
        }
    }

    return $convertExtent;
}

=begin nd
Function: isIntersected

Return TRUE if 2 geomtries intersect. They have to own the same spatial reference

Parameters (list):
    geom1 - <Geo::OGR::Geometry> - geometry 1
    geom2 - <Geo::OGR::Geometry> - geometry 2

Return (list):
    TRUE if intersect, FALSE otherwise
=cut
sub isIntersected {
    my $geom1 = shift;
    my $geom2 = shift;

    return $geom1->Intersect($geom2);
}


=begin nd
Function: getUnion

Return union of two geometries. They have to own the same spatial reference

Parameters (list):
    geom1 - <Geo::OGR::Geometry> - geometry 1
    geom2 - <Geo::OGR::Geometry> - geometry 2

Returns geometry union
=cut
sub getUnion {
    my $geom1 = shift;
    my $geom2 = shift;

    return $geom1->Union($geom2);
}

####################################################################################################
#                               Group: Export tools                                                #
####################################################################################################

=begin nd
Function: getWkt

Return the geometry as WKT

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    the WKT string
=cut
sub getWkt {
    my $geom = shift;

    return $geom->ExportToWkt();
}

=begin nd
Function: getJson

Return the geometry as JSON

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    the JSON string
=cut
sub getJson {
    my $geom = shift;

    return $geom->ExportToJson();
}

=begin nd
Function: getGml

Return the geometry as GML

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    the GML string
=cut
sub getGml {
    my $geom = shift;

    return $geom->ExportToGML();
}

=begin nd
Function: getKml

Return the geometry as KML

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    the KML string
=cut
sub getKml {
    my $geom = shift;

    return $geom->ExportToKML();
}

=begin nd
Function: getWkb

Return the geometry as hexadecimal WKB

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object

Return (list):
    the WKB string
=cut
sub getWkb {
    my $geom = shift;

    return $geom->AsHEXWKB();
}


=begin nd
Function: exportFile

Write geometry into a file. Detect format from extension.

Parameters (list):
    geom - <Geo::OGR::Geometry> - OGR geometry object
    path - string - Path to file to write

Return (list):
    TRUE if success, FALSE if failure
=cut
sub exportFile {
    my $geom = shift;
    my $path = shift;

    open(OUT, ">$path") or do {
        ERROR("Cannot open $path to write in it");
        return FALSE;
    };

    if ($path =~ m/\.kml$/) {
        print OUT getKml($geom);
    }
    elsif ($path =~ m/\.gml$/) {
        print OUT getGml($geom);
    }
    elsif ($path =~ m/\.json$/) {
        print OUT getJson($geom);
    }
    elsif ($path =~ m/\.wkb$/) {
        print OUT getWkb($geom);
    }
    else {
        print OUT getWkt($geom);
    }
    
    close(OUT);

    return TRUE;
}


####################################################################################################
#                               Group: Data informations functions                                 #
####################################################################################################


=begin nd
Function: getRasterInfos

Return the georeferencement (bbox, resolution) and pixel infos about an image

Parameters (list):
    filepath - string - Path of the referenced image
    type - string - Data type : Vector or Raster

Return (hash reference):
    Raster case
| {
|     dimensions => [width, height],
|     pixel => ROK4::Core::Pixel object,
|     resolutions => [xres, yres],
|     bbox => [xmin, ymin, xmax, ymax]
| }

    Vector case
| {
|     table => {
|            'final_name' => 'departement',
|            'attributes' => {
|                'ogc_fid' => {
|                    'count' => 101,
|                    'type' => 'integer'
|                },
|                'nom_dep' => {
|                    'type' => 'character varying(30)',
|                    'count' => 101
|                }
|            },
|            'geometry' => {
|                            'name' => 'wkb_geometry',
|                            'type' => 'MULTIPOLYGON'
|                            },
|            'native_name' => 'departement'
|     }
|     bbox => [xmin, ymin, xmax, ymax]
| }

    undefined if failure
=cut
sub get_informations {
    my $filepath = shift;
    my $type = shift;

    my $dataset;
    eval { $dataset= Geo::GDAL::Open({"Name" => $filepath, "Access" => 'ReadOnly', "Type" => $type}); };
    if ($@) {
        ERROR (sprintf "Can not open file ('%s') : '%s' !", $filepath, $@);
        return undef;
    }

    my $res = {};

    if ($type eq "Raster") {
        my $refgeo = $dataset->GetGeoTransform();
        if (! defined ($refgeo) || scalar (@$refgeo) != 6) {
            ERROR ("Can not found geometric parameters of image ('$filepath') !");
            return undef;
        }

        # forced formatting string !
        my ($xmin, $dx, $rx, $ymax, $ry, $ndy)= @{$refgeo};

        $res = {
            dimensions => [$dataset->{RasterXSize}, $dataset->{RasterYSize}],
            resolutions => [sprintf("%.12f", $dx), sprintf("%.12f", abs($ndy))],
            bbox => [
                sprintf("%.12f", $xmin),
                sprintf("%.12f", $ymax + $ndy*$dataset->{RasterYSize}),
                sprintf("%.12f", $xmin + $dx*$dataset->{RasterXSize}),
                sprintf("%.12f", $ymax)
            ],
        };

        # Pixel

        my $i = 0;

        my $DataType = undef;
        foreach my $objBand ($dataset->Bands()) {

            if (! defined $DataType) {
                $DataType = uc($objBand->DataType());
            } else {
                if (uc($objBand->DataType()) ne $DataType) {
                    ERROR (sprintf "DataType is not the same (%s and %s) for all band in this image !", uc($objBand->DataType()), $DataType);
                    return undef;
                }
            }
            
            $i++;
        }

        my $Band = $i;
        my $sampleformat = undef;

        if ($DataType eq "BYTE") {
            $sampleformat  = "UINT8";
        }
        else {
            $sampleformat = $DataType;
        }
        
        $res->{pixel} = ROK4::Core::Pixel->new({
            sampleformat => $sampleformat,
            samplesperpixel => $Band
        });

        
    } elsif ($type eq "Vector") {

# |     table => {
# |            'final_name' => 'departement',
# |            'attributes' => {
# |                'ogc_fid' => {
# |                    'count' => 101,
# |                    'type' => 'integer'
# |                },
# |                'nom_dep' => {
# |                    'type' => 'character varying(30)',
# |                    'count' => 101
# |                }
# |            },
# |            'geometry' => {
# |                 'type' => 'MULTIPOLYGON'
# |            },
# |        }

        my $layer;
        eval {
            $layer = $dataset->GetLayer();
            my %schema = $layer->Schema();

            my $table = {
                final_name => $schema{"Name"},
                attributes => {},
                geometry => {
                    type => undef
                }
            };

            for my $field (@{$schema{"Fields"}}) {
                if (exists $field->{"SpatialReference"}) {

                    if (exists $res->{"geometry"}) {
                        die("$filepath: multi geometry layer");
                    }

                    $table->{geometry}->{type} = $field->{"Type"};
                } else {

                    my $count = $dataset->ExecuteSQL(sprintf("SELECT count(DISTINCT %s) FROM %s", $field->{"Name"}, $schema{"Name"}));

                    $table->{attributes}->{$field->{"Name"}} = {
                        "type" => $field->{"Type"},
                        "count" => $count->GetNextFeature()->GetField(0)
                    };
                }
            }

            $res->{table} = $table;
        };

        if ($@) {
            ERROR ("Can not get vector infos from file ('$filepath')");
            ERROR (sprintf "$@ ");
            return undef;
        }

        eval {
            my $extent = $layer->GetExtent();
            $res->{"bbox"} = [
                $extent->[0],
                $extent->[2],
                $extent->[1],
                $extent->[3]
            ];
        };

        if ($@) {
            # A priori la géométrie détectée ne permet pas de calculer l'étendue (CSV vide par exemple)
            ERROR (sprintf "Cannot determine vector data extent");
            return undef;
        }
    }

    return $res;
}


####################################################################################################
#                               Group: Spatial Reference functions                                 #
####################################################################################################

=begin nd
Function: spatialReferenceFromSRS

Return an OSR spatial reference from a SRS string.

Parameters (list):
    srs - string - SRS string, whose authority is known by proj

Return :
    a <Geo::OSR::SpatialReference> object, undef if failure
=cut
sub spatialReferenceFromSRS {
    my $srs = shift;

    my $sr;
    if ($gdalVersion =~ /^2|3/) {
        #version 2.x    
        eval { $sr = Geo::OSR::SpatialReference->new(Proj4 => '+init='.$srs.' +wktext'); };
        if ($@) {
            eval { $sr = Geo::OSR::SpatialReference->new(Proj4 => '+init='.lc($srs).' +wktext'); };
            if ($@) {
                ERROR("$@");
                ERROR (sprintf "Impossible to initialize the spatial coordinate system (%s) to know if coordinates have to be reversed !\n",$srs);
                return undef;
            }
        }
    } elsif ($gdalVersion =~ /^1/) {
        #version 1.x
        # Have coodinates to be reversed ?
        $sr= new Geo::OSR::SpatialReference;
        eval { $sr->ImportFromProj4('+init='.$srs.' +wktext'); };
        if ($@) {
            eval { $sr->ImportFromProj4('+init='.lc($srs).' +wktext'); };
            if ($@) {
                ERROR("$@");
                ERROR (sprintf "Impossible to initialize the spatial coordinate system (%s) to know if coordinates have to be reversed !\n",$srs);
                return undef;
            }
        }
    }

    return $sr;
}

=begin nd
Function: isGeographic

Parameters (list):
    srs - a <Geo::OSR::SpatialReference> - SRS to test if geographic

=cut
sub isGeographic {
    my $sr = shift;
    return $sr->IsGeographic();
}


=begin nd
Function: coordinateTransformationFromSpatialReference

Return an OSR coordinate transformation from a source and a destination spatial references.

Parameters (list):
    src - string - Source spatial reference, whose authority is known by proj4
    dst - string - Destination spatial reference, whose authority is known by proj4

Return :
    a <Geo::OSR::CoordinateTransformation> object, undef if failure
=cut
sub coordinateTransformationFromSpatialReference {
    my $src = shift;
    my $dst = shift;
    
    my $srcSR = ROK4::Core::ProxyGDAL::spatialReferenceFromSRS($src);
    if (! defined $srcSR) {
        ERROR(sprintf "Impossible to initialize the initial spatial coordinate system (%s) !", $src);
        return undef;
    }

    my $dstSR = ROK4::Core::ProxyGDAL::spatialReferenceFromSRS($dst);
    if (! defined $dstSR) {
        ERROR(sprintf "Impossible to initialize the destination spatial coordinate system (%s) !", $dst);
        return undef;
    }

    my $ct = Geo::OSR::CoordinateTransformation->new($srcSR, $dstSR);

    return $ct;
}

=begin nd
Function: transformPoint

Convert a XY point, thanks to provided coordinate tranformation

Parameters (list):
    x - float - x of point to converted
    y - float - y of point to converted
    ct - <Geo::OSR::CoordinateTransformation> - Coordinate transformation to use to reproject the point

Return (list) :
    (reprojX, reprojY), x is undef if failure
=cut
sub transformPoint {
    my $x = shift;
    my $y = shift;
    my $ct = shift;

    my $p = 0;
    eval {
        $ENV{OGR_ENABLE_PARTIAL_REPROJECTION} = TRUE;
        $p = $ct->TransformPoint($x,$y);
    };
    if ($@) {
        ERROR($@);
        ERROR("Cannot tranform point %s, %s", $x, $y);
        return (undef, undef);
    }

    return ($p->[0], $p->[1]);
}

=begin nd
Function: convertBBox

Not just convert corners, but 7 points on each side, to determine reprojected bbox. Use OSR library.

Parameters (list):
    ct - <Geo::OSR::CoordinateTransformation> - To convert bbox. Can be undefined (no reprojection).
    bbox - double array - xmin,ymin,xmax,ymax

Returns the converted (according to the given CoordinateTransformation) bbox as a double array (xMin, yMin, xMax, yMax), (0,0,0,0) if error.
=cut
sub convertBBox {
    my $ct = shift;
    my @bbox = @_;

    if (! defined($ct)){
        $bbox[0] = Math::BigFloat->new($bbox[0]);
        $bbox[1] = Math::BigFloat->new($bbox[1]);
        $bbox[2] = Math::BigFloat->new($bbox[2]);
        $bbox[3] = Math::BigFloat->new($bbox[3]);
        return @bbox;
    }

    my $geom = geometryFromBbox(@bbox);

    eval { 
        $ENV{OGR_ENABLE_PARTIAL_REPROJECTION} = TRUE;
        $geom->Transform($ct);
    };
    if ($@) {
        ERROR(sprintf "Impossible to transform bbox (@bbox). Probably limits are reached ! : $@" );
        return (0,0,0,0);
    }

    my ($xmin, $xmax, $ymin, $ymax) = $geom->GetEnvelope();

    my $margeX = ($xmax - $xmin) * 0.02; # FIXME: la taille de la marge est arbitraire!!
    my $margeY = ($ymax - $ymax) * 0.02; # FIXME: la taille de la marge est arbitraire!!

    $xmin -= $margeX;
    $ymin -= $margeY;
    $xmax += $margeX;
    $ymax += $margeY;

    return ($xmin,$ymin,$xmax,$ymax);
}

1;
__END__
