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
File: GeoImage.pm

Class: ROK4::Core::GeoImage

(see libperlauto/ROK4_Core_GeoImage.png)

Describes a georeferenced image and enable to know its components.

Using:
    (start code)
    use ROK4::Core::GeoImage;

    # GeoImage object creation
    my $objGeoImage = ROK4::Core::GeoImage->new("/home/ign/DATA/XXXXX_YYYYY.tif");
    (end code)

Attributes:
    completePath - string - Complete path (/home/ign/DATA/XXXXX_YYYYY.tif)
    filename - string - Just the image name, with file extension (XXXXX_YYYYY.tif).
    filepath - string - The directory which contain the image (/home/ign/DATA)
    maskCompletePath - string - Complete path of associated mask, if exists (undef otherwise).
    srs - string - Projection of image
    xmin - double - Bottom left corner X coordinate.
    ymin - double - Bottom left corner Y coordinate.
    xmax - double - Top right corner X coordinate.
    ymax - double - Top right corner Y coordinate.
    xres - double - X wise resolution (in SRS unity).
    yres - double - Y wise resolution (in SRS unity).
    height - integer - Pixel height.
    width - integer - Pixel width.
    pixel - <ROK4::Core::Pixel> - Pixel infos.
    
=cut

################################################################################

package ROK4::Core::GeoImage;

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

GeoImage constructor. Bless an instance.

Parameters (list):
    completePath - string - Complete path to the image file.
    srs - string - Projection of georeferenced image

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
        maskCompletePath => undef,
        srs => undef,
        xmin => undef,
        ymax => undef,
        xmax => undef,
        ymin => undef,
        xres => undef,
        yres => undef,
        height => undef,
        width => undef,
        pixel => undef
    };

    bless($this, $class);

    # init. class
    return undef if (! $this->_init($completePath, $srs));

    return $this;
}

=begin nd
Function: _init

Checks and stores file's informations.

Search a potential associated data mask : A file with the same base name but the extension *.msk*.

Parameters (list):
    completePath - string - Complete path to the image file.
    srs - string - Projection of georeferenced image
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
        
    my $maskPath = $completePath;
    $maskPath =~ s/\.[a-zA-Z0-9]+$/\.msk/;
    
    if (-f $maskPath) {
        INFO(sprintf "We have a mask associated to the image '%s' :\t%s",$completePath,$maskPath);
        $this->{maskCompletePath} = $maskPath;
    }
    
    #
    $this->{filepath} = File::Basename::dirname($completePath);
    $this->{filename} = File::Basename::basename($completePath);

    my $infos = ROK4::Core::ProxyGDAL::get_informations($completePath, "Raster");
    if (! defined $infos) {
        ERROR ("Cannot extract infos from $completePath");
        return FALSE;        
    }

    $this->{xmin} = $infos->{bbox}->[0];
    $this->{ymin} = $infos->{bbox}->[1];
    $this->{xmax} = $infos->{bbox}->[2];
    $this->{ymax} = $infos->{bbox}->[3];

    $this->{xres} = $infos->{resolutions}->[0];
    $this->{yres} = $infos->{resolutions}->[1];

    $this->{width} = $infos->{dimensions}->[0];
    $this->{height} = $infos->{dimensions}->[1];

    $this->{pixel} = $infos->{pixel};

    return TRUE;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################

=begin nd
Function: getPixel
=cut
sub getPixel {
    my $this = shift;

    return $this->{pixel};
}

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

# Function: getWidth
sub getWidth {
  my $this = shift;
  return $this->{width};
}

# Function: getHeight
sub getHeight {
  my $this = shift;
  return $this->{height};
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

# Function: getXres
sub getXres {
  my $this = shift;
  return $this->{xres};  
}

# Function: getYres
sub getYres {
  my $this = shift;
  return $this->{yres};  
}

# Function: getName
sub getName {
  my $this = shift;
  return $this->{filename}; 
}

####################################################################################################
#                                Group: Export methods                                             #
####################################################################################################

=begin nd
Function: exportForMntConf

Export a GeoImage object as a string. Output is formated to be used by mergeNtiff generation.

Parameters:
    useMask - boolean - Do we export mask into configuration

Example:
|    IMG completePath xmin ymax xmax ymin xres yres
|    MSK maskCompletePath
=cut
sub exportForMntConf {
    my $this = shift;
    my $useMask = shift;

    my $output = sprintf "IMG %s\t%s", $this->{completePath}, $this->{srs};

    $output .= sprintf "\t%s\t%s\t%s\t%s\t%s\t%s\n",
        $this->{xmin}, $this->{ymax}, $this->{xmax}, $this->{ymin},
        $this->{xres}, $this->{yres};
        
    if ($useMask && defined $this->{maskCompletePath}) {
        $output .= sprintf "MSK %s\n", $this->{maskCompletePath};
    }

    return $output;
}

1;
__END__
