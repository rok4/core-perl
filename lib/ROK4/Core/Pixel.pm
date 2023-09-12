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
File: Pixel.pm

Class: ROK4::Core::Pixel

(see libperlauto/ROK4_Core_Pixel.png)

Store all pixel's intrinsic components.

Using:
    (start code)
    use ROK4::Core::Pixel;

    my $objC = ROK4::Core::Pixel->new({
        sampleformat => "UINT8",
        samplesperpixel => 3
    });
    (end code)

Attributes:
    photometric - string - Samples' interpretation.
    sampleformat - string - Basic sample format, int or float.
    bitspersample - integer - Number of bits per sample (the same for all samples).
    samplesperpixel - integer - Number of channels.
=cut

################################################################################

package ROK4::Core::Pixel;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Data::Dumper;

use ROK4::Core::Array;


################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

# Constant: PHOTOMETRICS
# Define allowed values for attribute photometric
my @PHOTOMETRICS = ('rgb','gray','mask');

# Constant: DEFAULT_PHOTOMETRICS
# Define default photometrics according to SAMPLESPERPIXELS
my %DEFAULT_PHOTOMETRICS = (
    1 => 'gray',
    2 => 'gray',
    3 => 'rgb',
    4 => 'rgb'
);

# Constant: SAMPLESPERPIXELS
# Define allowed values for attribute samplesperpixel
my @SAMPLESPERPIXELS = (1,2,3,4);

# Constant: SAMPLEFORMATS
# Define allowed values for attribute sampleformat, and splitted informations
my %SAMPLEFORMATS = (
    'INT8' => ['uint', 8],
    'UINT8' => ['uint', 8],
    'FLOAT32' => ['float', 32]
);

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

Pixel constructor. Bless an instance. Check and store attributes values.

Parameters (hash):
    sampleformat - string - Sample format, type.
    samplesperpixel - integer - Number of channels.
    photometric - string - Optionnal, samples' interpretation. Default value : "rgb".
=cut
sub new {
    my $class = shift;
    my $params = shift;

    $class = ref($class) || $class;
    # IMPORTANT : if modification, think to update natural documentation (just above)
    my $this = {
        photometric => undef,
        sampleformat => undef,
        bitspersample => undef,
        samplesperpixel => undef
    };

    bless($this, $class);

    # All attributes have to be present in parameters and defined

    ### Sample format : REQUIRED
    if (! exists $params->{sampleformat} || ! defined $params->{sampleformat}) {
        ERROR ("'sampleformat' required !");
        return undef;
    } else {
        if (! exists $SAMPLEFORMATS{$params->{sampleformat}}) {
            ERROR (sprintf "Unknown 'sampleformat' : %s !",$params->{sampleformat});
            return undef;
        }

        $this->{sampleformat} = $SAMPLEFORMATS{$params->{sampleformat}}[0];
        $this->{bitspersample} = $SAMPLEFORMATS{$params->{sampleformat}}[1];
    }    

    ### Samples per pixel : REQUIRED
    if (! exists $params->{samplesperpixel} || ! defined $params->{samplesperpixel}) {
        ERROR ("'samplesperpixel' required !");
        return undef;
    } else {
        if (! defined ROK4::Core::Array::isInArray($params->{samplesperpixel}, @SAMPLESPERPIXELS)) {
            ERROR (sprintf "Unknown 'samplesperpixel' : %s !",$params->{samplesperpixel});
            return undef;
        }
        $this->{samplesperpixel} = int($params->{samplesperpixel});
    }

    ### Photometric :  OPTIONNAL
    if (! exists $params->{photometric} || ! defined $params->{photometric}) {
        $this->{photometric} = $DEFAULT_PHOTOMETRICS{$this->{samplesperpixel}};
    } else {
        if (! defined ROK4::Core::Array::isInArray($params->{photometric}, @PHOTOMETRICS)) {
            ERROR (sprintf "Unknown 'photometric' : %s !",$params->{photometric});
            return undef;
        }
        $this->{photometric} = $params->{photometric};
    }

    return $this;
}

####################################################################################################
#                                Group: Getters - Setters                                          #
####################################################################################################


# Function: validateNodata
sub validateNodata {
    my $this = shift;
    my $nodata = shift;

    if (scalar(@{$nodata} != $this->{samplesperpixel})) {
        ERROR (sprintf "Nodata have to provide %s values", $this->{samplesperpixel});
        return FALSE;
    }

    return TRUE;
}

# Function: getPhotometric
sub getPhotometric {
    my $this = shift;
    return $this->{photometric};
}

# Function: getSampleFormat
sub getSampleFormat {
    my $this = shift;
    return $this->{sampleformat};
}

# Function: getSampleFormatCode
sub getSampleFormatCode {
    my $this = shift;
    return sprintf "%s%s", uc($this->{sampleformat}), $this->{bitspersample};
}

# Function: getBitsPerSample
sub getBitsPerSample {
    my $this = shift;
    return $this->{bitspersample};
}

# Function: getSamplesPerPixel
sub getSamplesPerPixel {
    my $this = shift;
    return $this->{samplesperpixel};
}

# Function: equals
sub equals {
    my $this = shift;
    my $other = shift;

    return (
        $this->{samplesperpixel} eq $other->getSamplesPerPixel() &&
        $this->{sampleformat} eq $other->getSampleFormat() &&
        $this->{photometric} eq $other->getPhotometric() &&
        $this->{bitspersample} eq $other->getBitsPerSample()
    );
}

=begin nd
Function: convertible

Tests if conversion is allowed between two pixel formats

Parameters (list):
    other - <ROK4::Core::Pixel> - Destination pixel for conversion to test
=cut
sub convertible {
    my $this = shift;
    my $other = shift;

    if ($this->equals($other)) {
        return TRUE;
    }


    # La conversion se fait par la classe de la libimage PixelConverter, dont une instance est ajoutée à un FileImage pour convertir à la volée
    # Les tests de faisabilité ici doivent être identiques à ceux dans PixelConverter :
    # ----------------------------- PixelConverter constructor : C++ ----------------------------------
    # if (inSampleFormat == SampleFormat::FLOAT || outSampleFormat == SampleFormat::FLOAT) {
    #     BOOST_LOG_TRIVIAL(warning) << "PixelConverter doesn't handle float samples";
    #     return;
    # }
    # if (inSampleFormat != outSampleFormat) {
    #     BOOST_LOG_TRIVIAL(warning) << "PixelConverter doesn't handle different samples format";
    #     return;
    # }
    # if (inBitsPerSample != outBitsPerSample) {
    #     BOOST_LOG_TRIVIAL(warning) << "PixelConverter doesn't handle different number of bits per sample";
    #     return;
    # }

    # if (inSamplesPerPixel == outSamplesPerPixel) {
    #     BOOST_LOG_TRIVIAL(warning) << "PixelConverter have not to be used if number of samples per pixel is the same";
    #     return;
    # }

    # if (inBitsPerSample != 8) {
    #     BOOST_LOG_TRIVIAL(warning) << "PixelConverter only handle 8 bits sample";
    #     return;
    # }
    # -------------------------------------------------------------------------------------------------

    if ($this->getSampleFormat() eq "float" || $other->getSampleFormat() eq "float") {
        # aucune conversion pour des canaux flottant
        return FALSE;
    }

    if ($this->getSampleFormat() ne $other->getSampleFormat()) {
        return FALSE;
    }

    if ($this->getBitsPerSample() != $other->getBitsPerSample()) {
        return FALSE;
    }

    if ($this->getBitsPerSample() != 8) {
        return FALSE;
    }

    return TRUE;
}

1;
__END__
