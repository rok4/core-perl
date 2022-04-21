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
File: GeoVector.pm

Class: ROK4::Core::GeoVector

(see libperlauto/Core_GeoVector.png)

Describes a georeferenced image and enable to know its components.

Using:
    (start code)
    use ROK4::Core::GeoVector;

    # GeoVector object creation
    my $objGeoVector = ROK4::Core::GeoVector->new("/home/ign/DATA/XXXXX_YYYYY.dbf");
    (end code)

Attributes:
    completePath - string - Complete path (/home/ign/DATA/XXXXX_YYYYY.dbf)
    filename - string - Just the image name, with file extension (XXXXX_YYYYY.dbf).
    filepath - string - The directory which contain the image (/home/ign/DATA)
    srs - string - Projection of file
    xmin - double - Bottom left corner X coordinate.
    ymin - double - Bottom left corner Y coordinate.
    xmax - double - Top right corner X coordinate.
    ymax - double - Top right corner Y coordinate.
    table - hash - all informations about vector data
|         {
|            'filter' => '',
|            'final_name' => 'departement',
|            'attributes' => {
|                'ogc_fid' => {
|                    'count' => 101,
|                    'type' => 'integer'
|                },
|                'nom_dep' => {
|                    'type' => 'character varying(30)',
|                    'count' => 101
|                },
|                'insee_reg' => {
|                    'type' => 'character varying(2)',
|                    'count' => 18
|                },
|                'chf_dep' => {
|                    'count' => 101,
|                    'type' => 'character varying(5)'
|                },
|               'id' => {
|                    'count' => 101,
|                    'type' => 'character varying(24)'
|                },
|                'insee_dep' => {
|                    'type' => 'character varying(3)',
|                    'count' => 101
|                },
|                'nom_dep_m' => {
|                    'count' => 101,
|                    'type' => 'character varying(30)'
|                }
|            },
|            'geometry' => {
|                            'name' => 'wkb_geometry',
|                            'type' => 'MULTIPOLYGON'
|                            },
|            'native_name' => 'departement'
|        }
    
=cut

################################################################################

package ROK4::Core::GeoVector;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;

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

GeoVector constructor. Bless an instance.

Parameters (list):
    completePath - string - Complete path to the vector file.
    srs - string - Projection of data

See also:
    <_init>
=cut
sub new {
    my $class = shift;
    my $completePath = shift;
    my $srs = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        completePath => undef,
        filename => undef,
        filepath => undef,
        srs => undef,
        xmin => undef,
        ymax => undef,
        xmax => undef,
        ymin => undef,
        table => undef
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($completePath, $srs));

    return $this;
}

=begin nd
Function: _init

Checks and stores file's informations.

Parameters (list):
    completePath - string - Complete path to the vector file.
    srs - string - Projection of data
=cut
sub _init {
    my $this   = shift;
    my $completePath = shift;
    my $srs = shift;

    return FALSE if (! defined $completePath);
    return FALSE if (! defined $srs);

    $this->{srs} = $srs;
    
    if (! -f $completePath) {
        ERROR ("File doesn't exist !");
        return FALSE;
    }
    
    # init. params
    $this->{completePath} = $completePath;
    
    #
    $this->{filepath} = File::Basename::dirname($completePath);
    $this->{filename} = File::Basename::basename($completePath);

    my $infos = ROK4::Core::ProxyGDAL::get_informations($completePath, "Vector");
    if (! defined $infos) {
        ERROR ("Cannot extract informations from $completePath");
        return FALSE;        
    }

    if (! exists $infos->{bbox}) {
        ERROR (sprintf "Cannot calculate an extent from %s, is it geometric data ?", $this->{filename});
        return FALSE;
    }

    $this->{xmin} = $infos->{bbox}->[0];
    $this->{ymin} = $infos->{bbox}->[1];
    $this->{xmax} = $infos->{bbox}->[2];
    $this->{ymax} = $infos->{bbox}->[3];

    $this->{table} = $infos->{table};

    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

=begin nd
Function: getBBox

Return the image's bbox as a double array [xMin, yMin, xMax, yMax], source SRS.
=cut
sub getBBox {
  my $this = shift;
  return ($this->{xmin},$this->{ymin},$this->{xmax},$this->{ymax});
}

# Function: getSRS
sub getSRS {
  my $this = shift;
  return $this->{srs};
}

# Function: getXmin
sub getXmin {
  my $this = shift;
  return $this->{xmin};
}

# Function: getYmin
sub getYmin {
  my $this = shift;
  return $this->{ymin};
}

# Function: getXmax
sub getXmax {
  my $this = shift;
  return $this->{xmax};
}

# Function: getYmax
sub getYmax {
  my $this = shift;
  return $this->{ymax};
}

# Function: getName
sub getName {
  my $this = shift;
  return $this->{filename}; 
}

# Function: getTable
sub getTable {
  my $this = shift;
  return $this->{table}; 
}

# Function: getCompletePath
sub getCompletePath {
  my $this = shift;
  return $this->{completePath}; 
}

1;
__END__
