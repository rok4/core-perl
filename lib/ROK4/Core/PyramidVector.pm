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
File: PyramidVector.pm

Class: ROK4::Core::PyramidVector

(see libperlauto/ROK4_Core_PyramidVector.png)

Store all informations about a vector pyramid, whatever the storage type.

Using:
    (start code)
    use ROK4::Core::PyramidVector;

    # To create a new FILE pyramid, "to write"
    my $newPyramid = ROK4::Core::PyramidVector->new("VALUES", {
        pyr_name_new => "TOTO",

        tms_name => "PM",

        image_width => 16,
        image_height => 16,

        pyr_data_path => "/path/to/data/directory",
        dir_depth => 2
    });

    if (! defined $newPyramid) {
        ERROR("Cannot create the new file pyramid");
    }

    # To load an existing pyramid, "to read" (XML)
    my $readPyramid = ROK4::Core::PyramidVector->new("DESCRIPTOR", "/path/to/an/existing/pyramid.pyr");
    # or to load an existing pyramid, "to read" (JSON)
    my $readPyramid = ROK4::Core::PyramidVector->new("DESCRIPTOR", "/path/to/an/existing/pyramid.json");

    if (! defined $readPyramid) {
        ERROR("Cannot load the pyramid");
    }

    (end code)

Attributes:
    name - string - Pyramid's name

    image_width - integer - Number of tile in an pyramid's image, widthwise.
    image_height - integer - Number of tile in an pyramid's image, heightwise.

    tms - <ROK4::Core::TileMatrixSet> - Pyramid's images will be cutted according to this TMS grid.
    levels - <ROK4::Core::LevelVector> hash - Key is the level ID, the value is the <ROK4::Core::LevelVector> object. Define levels present in the pyramid.

    storage_type - string - Storage type of data : FILE, S3, SWIFT or CEPH

    data_path - string - Directory in which we write the pyramid's data if FILE storage type
    dir_depth - integer - Number of subdirectories from the level root to the image if FILE storage type : depth = 2 => /.../LevelID/SUB1/SUB2/DATA.tif

    data_bucket - string - Name of the (existing) S3 bucket, where to store data if S3 storage type

    data_container - string - Name of the (existing) Swift container, where to store data if Swift storage type

    data_pool - string - Name of the (existing) CEPH pool, where to store data if CEPH storage type

    cachedList - string hash - If loaded, list content in an hash.
    listCached - boolean - Precise if the list has been loaded
    cachedListModified - boolean - Precise if cached list has been modified
=cut

################################################################################

package ROK4::Core::PyramidVector;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use XML::LibXML;
use Encode qw(decode encode);

use File::Basename;
use File::Spec;
use File::Path;
use File::Copy;
use Tie::File;
use Cwd;
use JSON qw( );
use JSON::Parse qw(assert_valid_json parse_json);

use Data::Dumper;

use ROK4::Core::LevelVector;
use ROK4::Core::Array;
use ROK4::Core::ProxyStorage;

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

# Constant: DEFAULT
# Define default values for attributes dir_depth.
my %DEFAULT = (
    dir_depth => 2
);

################################################################################

BEGIN {}
INIT {}
END {}

####################################################################################################
#                                        Group: Constructors                                       #
####################################################################################################

=begin nd
Constructor: new

Pyramid constructor. Bless an instance.

Parameters (list):
    type - string - VALUES
    params - hash - All parameters about the new pyramid, "pyramid" section of the be4 configuration file
       or
    type - string - DESCRIPTOR
    params - string - Path to the pyramid's descriptor to load

    ancestor - <ROK4::Core::PyramidVector> - Optionnal, to provide if we want to use parameters from ancestor 

See also:
    <_createFromXML>, <_createFromJSON>, <_load>
=cut
sub new {
    my $class = shift;
    my $type = shift;
    my $params = shift;

    $class = ref($class) || $class;

    # IMPORTANT : if modification, think to update natural documentation (just above)

    my $this = {
        name => undef,

        # OUT
        image_width  => 16,
        image_height => 16,

        tms => undef,
        levels => {},

        storage_type => undef,
        # Pyramide FICHIER
        data_path => undef,
        dir_depth => undef,

        # Pyramide S3
        data_bucket => undef,
        
        # Pyramide SWIFT
        data_container => undef,

        # Pyramide CEPH
        data_pool => undef,

        # Cached list
        cachedList => {},
        listCached => FALSE,
        cachedListModified => FALSE
    };

    bless($this, $class);

    if ($type eq "DESCRIPTOR") {

        my $descriptor_path = $params;

        my $content = "";

        if ($descriptor_path =~ m/^file:\/\/(.+)$/) {

            if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables("FILE")) {
                ERROR("Environment variable is missing for a FILE storage");
                return undef;
            }

            (my $length, $content) = ROK4::Core::ProxyStorage::getData("FILE", $1);
            # On doit remplir ce data path pour que les éventuels chemins en relatifs dans les niveaux soit bien interprétés
            $this->{data_path} = File::Basename::dirname($1);
            # Le nom est le fichier sans extension
            $this->{name} = File::Basename::basename($1);
            $this->{name} =~ s/\.(pyr|json|)$//i;
        }
        elsif ($descriptor_path =~ m/^ceph:\/\/([^\/]+)\/(.+)$/) {

            if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables("CEPH")) {
                ERROR("Environment variable is missing for a CEPH storage");
                return undef;
            }

            (my $length, $content) = ROK4::Core::ProxyStorage::getData("CEPH", "$1/$2");
            # Le nom est l'objet sans extension
            $this->{name} = $2;
            $this->{name} =~ s/\.(pyr|json|)$//i;
        }
        elsif ($descriptor_path =~ m/^s3:\/\/([^\/]+)\/(.+)$/) {

            if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables("S3")) {
                ERROR("Environment variable is missing for a S3 storage");
                return undef;
            }

            (my $length, $content) = ROK4::Core::ProxyStorage::getData("S3", "$1/$2");
            # Le nom est l'objet sans extension
            $this->{name} = $2;
            $this->{name} =~ s/\.(pyr|json|)$//i;
        }
        elsif ($descriptor_path =~ m/^swift:\/\/([^\/]+)\/(.+)$/) {

            if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables("SWIFT")) {
                ERROR("Environment variable is missing for a SWIFT storage");
                return undef;
            }

            (my $length, $content) = ROK4::Core::ProxyStorage::getData("SWIFT", "$1/$2");
            # Le nom est l'objet sans extension
            $this->{name} = $2;
            $this->{name} =~ s/\.(pyr|json|)$//i;
        } else {
            ERROR ("Pyramid's descriptor storage unknown: $descriptor_path !");
            return undef;
        }

        if (! defined $content) {
            ERROR ("Pyramid's descriptor cannot be loaded : $descriptor_path !");
            return undef;
        }

        if ($descriptor_path =~ m/\.pyr$/i) {
            if (! $this->_createFromXML($content)) {
                ERROR ("Cannot create pyramid from XML descriptor");
                return undef;
            }
        }
        elsif ($descriptor_path =~ m/\.json$/i) {
            if (! $this->_createFromJSON($content)) {
                ERROR ("Cannot create pyramid from JSON descriptor");
                return undef;
            }
        } else {
            ERROR ("Cannot determine pyramid descriptor format from path (neither XML nor JSON) : $descriptor_path");
            return undef;
        }

    } else {
        # On crée une pyramide à partir de ses caractéristiques
        if (! $this->_createFromValues($params)) {
            ERROR ("Cannot create pyramid from values");
            return undef;
        }
    }


    if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables($this->{storage_type})) {
        ERROR(sprintf "Environment variable is missing for a %s storage", $this->{storage_type});
        return undef;
    }

    # Lier le TileMatrix à chaque niveau de la pyramide
    while (my ($id, $level) = each(%{$this->{levels}}) ) {
        if (! $level->bindTileMatrix($this->{tms})) {
            ERROR("Cannot bind a TileMatrix to pyramid's level $id");
            return FALSE;
        }
    }

    return $this;
}

=begin nd
Function: _createFromValues
=cut
sub _createFromValues {
    my $this = shift;
    my $params = shift;

    $this->{name} = $params->{name};

    # Stockage
    $this->{storage_type} = $params->{storage}->{type};
    if ($this->{storage_type} eq "FILE") {
        if ($this->{name} =~ /\//) {
            ERROR ("FILE pyramid name have not to contain slash");
            return FALSE;
        }
        $this->{data_path} = File::Spec->rel2abs($params->{storage}->{root});
        if (exists $params->{storage}->{depth}) {
            $this->{dir_depth} = $params->{storage}->{depth};
        } else {
            $this->{dir_depth} = $DEFAULT{dir_depth};
        }
    }
    elsif ($this->{storage_type} eq "S3") {
        $this->{data_bucket} = $params->{storage}->{root};
    }
    elsif ($this->{storage_type} eq "CEPH") {
        $this->{data_pool} = $params->{storage}->{root};
    }
    elsif ($this->{storage_type} eq "SWIFT") {
        $this->{data_container} = $params->{storage}->{root};
    }
    
    # TMS
    $this->{tms} = ROK4::Core::TileMatrixSet->new($params->{tms});
    if (! defined $this->{tms}) {
        ERROR(sprintf "Cannot create a TileMatrixSet object from the TMS name %s", $params->{tms});
        return FALSE;
    }
    
    # Slab size
    if (exists $params->{slab_size}) {
        $this->{image_width} = $params->{slab_size}->[0];
        $this->{image_height} = $params->{slab_size}->[1];
    }




    return TRUE;
}


=begin nd
Function: _createFromXML
=cut
sub _createFromXML {
    my $this   = shift;
    my $content = shift;
    my $params = shift;

    # read xml pyramid
    my $parser  = XML::LibXML->new();
    my $xmltree =  eval { $parser->parse_string($content); };

    if (! defined ($xmltree) || $@) {
        ERROR (sprintf "Can not read the XML content : $@ !");
        return FALSE;
    }

    my $root = $xmltree->getDocumentElement;

    # TMS
    my $tmsname = $root->findnodes('tileMatrixSet')->string_value();
    if ($tmsname eq '') {
        ERROR (sprintf "Can not extract 'tileMatrixSet' from the XML !");
        return FALSE;
    }
    $this->{tms} = ROK4::Core::TileMatrixSet->new($tmsname);
    if (! defined $this->{tms}) {
        ERROR("Cannot create a TileMatrixSet object from the TMS name $tmsname");
        return FALSE;
    }
    # FORMAT
    my $format = $root->findnodes('format')->string_value();
    if ($format eq '') {
        ERROR (sprintf "Can not extract 'format' in the XML !");
        return FALSE;
    }

    # load pyramid level
    my @levels = $root->getElementsByTagName('level');

    my $oneLevelId;
    my $storageType = undef;
    foreach my $v (@levels) {

        my $tagtm = $v->findvalue('tileMatrix');

        my $objLevel = ROK4::Core::LevelVector->new("XML", $v, $this->{data_path});
        if (! defined $objLevel) {
            ERROR(sprintf "Can not load the pyramid level : '%s'", $tagtm);
            return FALSE;
        }

        # On vérifie que tous les niveaux ont le même type de stockage
        if(defined $storageType && $objLevel->getStorageType() ne $storageType) {
            ERROR(sprintf "All level have to own the same storage type (%s -> %s != %s)", $tagtm, $objLevel->getStorageType(), $storageType);
            return FALSE;
        }
        $storageType = $objLevel->getStorageType();

        $this->{levels}->{$tagtm} = $objLevel;

        $oneLevelId = $tagtm;

        # same for each level
    }

    if (defined $oneLevelId) {
        $this->{image_width}  = $this->{levels}->{$oneLevelId}->getImageWidth();
        $this->{image_height} = $this->{levels}->{$oneLevelId}->getImageHeight();
        $this->{storage_type} = $storageType;

        if ($storageType eq "FILE") {
            my ($dd, $dp) = $this->{levels}->{$oneLevelId}->getDirsInfo();
            $this->{dir_depth} = $dd;
            $this->{data_path} = $dp;
        }
        elsif ($storageType eq "S3") {
            $this->{data_bucket} = $this->{levels}->{$oneLevelId}->getS3Info();
        }
        elsif ($storageType eq "SWIFT") {
            $this->{data_container} = $this->{levels}->{$oneLevelId}->getSwiftInfo();
        }
        elsif ($storageType eq "CEPH") {
            $this->{data_pool} = $this->{levels}->{$oneLevelId}->getCephInfo();
        }

    } else {
        # On a aucun niveau dans la pyramide à charger, il va donc nous manquer des informations : on sort en erreur
        ERROR("No level in the pyramid's descriptor");
        return FALSE;
    }

    return TRUE;
}


=begin nd
Function: _createFromJSON
=cut
sub _createFromJSON {
    my $this   = shift;
    my $content = shift;
    my $params = shift;

    eval { assert_valid_json ($content); };
    if ($@) {
        ERROR("Can not read the JSON content : $@");
        return FALSE;
    }

    my $pyramid_json_object = parse_json ($content);

    # TMS
    if (! exists $pyramid_json_object->{tile_matrix_set}) {
        ERROR (sprintf "Can not extract 'tile_matrix_set' from the JSON !");
        return FALSE;
    }

    $this->{tms} = ROK4::Core::TileMatrixSet->new($pyramid_json_object->{tile_matrix_set});
    if (! defined $this->{tms}) {
        ERROR("Cannot create a TileMatrixSet object from the TMS name ".$pyramid_json_object->{tile_matrix_set});
        return FALSE;
    }

    # FORMAT
    if (! exists $pyramid_json_object->{format}) {
        ERROR (sprintf "Can not extract 'format' from the JSON !");
        return FALSE;
    }

    # load pyramid level

    my $oneLevelId;
    my $storageType = undef;
    foreach my $v (@{$pyramid_json_object->{levels}}) {

        $oneLevelId = $v->{id};

        my $objLevel = ROK4::Core::LevelVector->new("JSON", $v, $this->{data_path});
        if (! defined $objLevel) {
            ERROR(sprintf "Can not load the pyramid level : '%s'", $oneLevelId);
            return FALSE;
        }

        # On vérifie que tous les niveaux ont le même type de stockage
        if(defined $storageType && $objLevel->getStorageType() ne $storageType) {
            ERROR(sprintf "All level have to own the same storage type (%s -> %s != %s)", $oneLevelId, $objLevel->getStorageType(), $storageType);
            return FALSE;
        }
        $storageType = $objLevel->getStorageType();

        $this->{levels}->{$oneLevelId} = $objLevel;

    }

    # same for each level
    if (defined $oneLevelId) {
        $this->{image_width}  = $this->{levels}->{$oneLevelId}->getImageWidth();
        $this->{image_height} = $this->{levels}->{$oneLevelId}->getImageHeight();

        $this->{storage_type} = $storageType;

        if ($storageType eq "FILE") {
            my ($dd, $dp) = $this->{levels}->{$oneLevelId}->getDirsInfo();
            $this->{dir_depth} = $dd;
            $this->{data_path} = $dp;
        }
        elsif ($storageType eq "S3") {
            $this->{data_bucket} = $this->{levels}->{$oneLevelId}->getS3Info();
        }
        elsif ($storageType eq "SWIFT") {
            $this->{data_container} = $this->{levels}->{$oneLevelId}->getSwiftInfo();
        }
        elsif ($storageType eq "CEPH") {
            $this->{data_pool} = $this->{levels}->{$oneLevelId}->getCephInfo();
        }

    } else {
        # On a aucun niveau dans la pyramide à charger, il va donc nous manquer des informations : on sort en erreur
        ERROR("No level in the pyramid's descriptor");
        return FALSE;
    }

    return TRUE;
}

####################################################################################################
#                                        Group: Update pyramid                                     #
####################################################################################################

=begin nd
Function: addLevel
=cut
sub addLevel {
    my $this = shift;
    my $level = shift;
    my $source = shift;

    if (exists $this->{levels}->{$level}) {
        # Le niveau existe déjà, ce qui est normal dans le cas d'une mise à jour
        return TRUE;
    }

    my $levelParams = {
        id => $level,
        tm => $this->{tms}->getTileMatrix($level),
        size => [$this->{image_width}, $this->{image_height}],
        tables => $source->getTables()
    };
    if ($this->{storage_type} eq "FILE") {
        # On doit ajouter un niveau stockage fichier
        $levelParams->{dir_data} = $this->getDataRoot();
        $levelParams->{dir_depth} = $this->{dir_depth};
    }
    elsif ($this->{storage_type} eq "CEPH") {
        # On doit ajouter un niveau stockage ceph
        $levelParams->{prefix} = $this->{name};
        $levelParams->{pool_name} = $this->{data_pool};
    }
    elsif ($this->{storage_type} eq "S3") {
        # On doit ajouter un niveau stockage s3
        $levelParams->{prefix} = $this->{name};
        $levelParams->{bucket_name} = $this->{data_bucket};
    }
    elsif ($this->{storage_type} eq "SWIFT") {
        # On doit ajouter un niveau stockage swift
        $levelParams->{prefix} = $this->{name};
        $levelParams->{container_name} = $this->{data_container};
    }

    $this->{levels}->{$level} = ROK4::Core::LevelVector->new("VALUES", $levelParams, $this->{data_path});

    if (! defined $this->{levels}->{$level}) {
        ERROR("Cannot create a Level object for level $level");
        return FALSE;
    }

    return TRUE;
}


=begin nd
Function: updateTMLimits
=cut
sub updateTMLimits {
    my $this = shift;
    my ($level,@bbox) = @_;
        
    $this->{levels}->{$level}->updateLimitsFromBbox(@bbox);
}


=begin nd
Function: updateStorageInfos
=cut
sub updateStorageInfos {
    my $this = shift;
    my $params = shift;

    my $type = $params->{type};

    # Environment variables nécessaire au stockage

    if (! ROK4::Core::ProxyStorage::checkEnvironmentVariables($type)) {
        ERROR("Environment variable is missing for a $type storage");
        return FALSE;
    }

    my $updateLevelParams = {};

    if ($type eq "FILE") {
        $this->{storage_type} = "FILE";
        $this->{data_path} = File::Spec->rel2abs($params->{root});

        if ( defined $params->{depth}) {
            $this->{dir_depth} = $params->{depth};
        } else {
            $this->{dir_depth} = 2;
        }

        $this->{data_bucket} = undef;
        $this->{data_container} = undef;
        $this->{data_pool} = undef;

        $updateLevelParams->{desc_path} = $this->{data_path};
        $updateLevelParams->{dir_depth} = $this->{dir_depth};
        $updateLevelParams->{dir_data} = $this->getDataRoot();
    }
    elsif ($type eq "CEPH") {
        $this->{storage_type} = "CEPH";
        $this->{data_pool} = $params->{root};

        $this->{data_path} = undef;
        $this->{dir_depth} = undef;
        $this->{data_bucket} = undef;
        $this->{data_container} = undef;

        $updateLevelParams->{prefix} = $this->{name};
        $updateLevelParams->{pool_name} = $this->{data_pool};
    }
    elsif ($type eq "S3") {
        $this->{storage_type} = "S3";
        $this->{data_bucket} = $params->{root};

        $this->{data_path} = undef;
        $this->{dir_depth} = undef;
        $this->{data_container} = undef;
        $this->{data_pool} = undef;

        $updateLevelParams->{prefix} = $this->{name};
        $updateLevelParams->{bucket_name} = $this->{data_bucket};
    }
    elsif ($type eq "SWIFT") {
        $this->{storage_type} = "SWIFT";
        $this->{data_container} = $params->{root};

        $this->{data_path} = undef;
        $this->{dir_depth} = undef;
        $this->{data_bucket} = undef;
        $this->{data_pool} = undef;

        $updateLevelParams->{prefix} = $this->{name};
        $updateLevelParams->{container_name} = $this->{data_container};
    } else {
        ERROR("Unknown storage type $type");
        return FALSE;
    }

    while (my ($id, $level) = each(%{$this->{levels}}) ) {
        if (! $level->updateStorageInfos($updateLevelParams)) {
            ERROR("Cannot update storage infos for the pyramid's level $id");
            return FALSE;
        }
    }
}

####################################################################################################
#                                      Group: Pyramids comparison                                  #
####################################################################################################

=begin nd
Function: checkCompatibility

We control values, in order to have the same as the final pyramid.

Compatibility = it's possible to convert (different compression or samples per pixel).

Equals = all format's parameters are the same (not the content).

Return 0 if pyramids is not consistent, 1 if compatibility but not equals, 2 if equals

Parameters (list):
    other - <ROK4::Core::PyramidVector> - Pyramid to compare
=cut
sub checkCompatibility {
    my $this = shift;
    my $other = shift;

    if ($this->getStorageType() ne $other->getStorageType()) {
        return 0;
    }

    if ($this->getStorageType() eq "FILE") {
        if ($this->getDirDepth() != $other->getDirDepth()) {
            return 0;
        }
    } else {
        # Dans le cas d'un stockage objet, les contenants doivent être les mêmes
        if ($this->getStorageRoot() ne $other->getStorageRoot() ) {
            return 0;
        }
    }

    if ($this->getTilesPerWidth() != $other->getTilesPerWidth()) {
        return 0;
    }
    if ($this->getTilesPerHeight() != $other->getTilesPerHeight()) {
        return 0;
    }

    if ($this->getTileMatrixSet()->getName() ne $other->getTileMatrixSet()->getName()) {
        return 0;
    }

    if ($this->getFormatCode() ne $other->getFormatCode()) {
        return 0;
    }

    return 2;
}

####################################################################################################
#                                      Group: Write functions                                     #
####################################################################################################


=begin nd
Function: writeDescriptor
=cut
sub writeDescriptor {
    my $this = shift;

    my $pyramid_json_object = {
        tile_matrix_set => $this->{tms}->getName(),
        format => $this->getFormatCode(),
        levels => []
    };

    my @orderedLevels = sort {$a->getOrder() <=> $b->getOrder()} ( values %{$this->{levels}});

    for (my $i = scalar(@orderedLevels) - 1; $i >= 0; $i--) {
        # we write levels in pyramid's descriptor from the top to the bottom
        push(@{$pyramid_json_object->{levels}}, $orderedLevels[$i]->exportToJsonObject());
    }

    # Écriture sur le stockage des données

    my $descPath = $this->getDescriptorPath();

    my $data = encode("utf-8", JSON::to_json($pyramid_json_object));
    if (! ROK4::Core::ProxyStorage::setData($this->{storage_type}, $descPath, $data)) {
        ERROR("Cannot write pyramid's descriptor to final location");
        return FALSE;
    }

    return TRUE;

}


####################################################################################################
#                                Group: Common getters                                             #
####################################################################################################

# Function: getFormatCode
sub getFormatCode {
    my $this = shift;
    return "TIFF_PBF_MVT";
}

# Function: getName
sub getName {
    my $this = shift;    
    return $this->{name};
}


# Function: getDescriptorPath
sub getDescriptorPath {
    my $this = shift;

    return File::Spec->catdir($this->getStorageRoot(), $this->{name}.".json");
}

# Function: getListPath
sub getListPath {
    my $this = shift;

    return File::Spec->catdir($this->getStorageRoot(), $this->{name}.".list");
}

# Function: getTileMatrixSet
sub getTileMatrixSet {
    my $this = shift;
    return $this->{tms};
}


=begin nd
Function: getSlabPath

Returns the theoric slab path, undef if the level is not present in the pyramid

Parameters (list):
    type - string - DATA
    level - string - Level ID
    col - integer - Slab column
    row - integer - Slab row
    full - boolean - In file storage case, precise if we want full path or juste the end (without data root)
=cut
sub getSlabPath {
    my $this = shift;
    my $type = shift;
    my $level = shift;
    my $col = shift;
    my $row = shift;
    my $full = shift;

    if (! exists $this->{levels}->{$level}) {
        return undef;
    }

    return $this->{levels}->{$level}->getSlabPath($type, $col, $row, $full);
}

# Function: getTilesPerWidth
sub getTilesPerWidth {
    my $this = shift;
    return $this->{image_width};
}

# Function: getTilesPerHeight
sub getTilesPerHeight {
    my $this = shift;
    return $this->{image_height};
}

=begin nd
Function: getSlabSize

Returns the pyramid's image's pixel width and height as the double list (width, height), for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getSlabSize {
    my $this = shift;
    my $level = shift;
    return ($this->getSlabWidth($level), $this->getSlabHeight($level));
}

=begin nd
Function: getSlabWidth

Returns the pyramid's image's pixel width, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getSlabWidth {
    my $this = shift;
    my $level = shift;

    return $this->{image_width} * $this->{tms}->getTileWidth($level);
}

=begin nd
Function: getSlabHeight

Returns the pyramid's image's pixel height, for a given level.

Parameters (list):
    level - string - Level ID
=cut
sub getSlabHeight {
    my $this = shift;
    my $level = shift;

    return $this->{image_height} * $this->{tms}->getTileHeight($level);
}

# Function: getLevel
sub getLevel {
    my $this = shift;
    my $level = shift;
    return $this->{levels}->{$level};
}

# Function: getBottomID
sub getBottomID {
    my $this = shift;

    my $order = undef;
    my $id = undef;
    while (my ($levelID, $level) = each(%{$this->{levels}})) {
        my $o = $level->getOrder();
        if (! defined $order || $o < $order) {
            $order = $o;
            $id = $levelID;
        }
    }

    return $id;
}

# Function: getBottomOrder
sub getBottomOrder {
    my $this = shift;

    my $order = undef;
    while (my ($levelID, $level) = each(%{$this->{levels}})) {
        my $o = $level->getOrder();
        if (! defined $order || $o < $order) {
            $order = $o;
        }
    }

    return $order;
}

# Function: getTopID
sub getTopID {
    my $this = shift;

    my $order = undef;
    my $id = undef;
    while (my ($levelID, $level) = each(%{$this->{levels}})) {
        my $o = $level->getOrder();
        if (! defined $order || $o > $order) {
            $order = $o;
            $id = $levelID;
        }
    }

    return $id;
}

# Function: getTopOrder
sub getTopOrder {
    my $this = shift;

    my $order = undef;
    while (my ($levelID, $level) = each(%{$this->{levels}})) {
        my $o = $level->getOrder();
        if (! defined $order || $o > $order) {
            $order = $o;
        }
    }

    return $order;
}

# Function: getLevels
sub getLevels {
    my $this = shift;
    return values %{$this->{levels}};
}


# Function: getOrderedLevels
sub getOrderedLevels {
    my $this = shift;

    return sort {$a->getOrder <=> $b->getOrder} ( values %{$this->{levels}});
}

=begin nd
Function: hasLevel

Precises if the provided level exists in the pyramid.

Parameters (list):
    levelID - string - Identifiant of the asked level
=cut
sub hasLevel {
    my $this = shift;
    my $levelID = shift;

    if (defined $levelID && exists $this->{levels}->{$levelID}) {
        return TRUE;
    }

    return FALSE;
}


####################################################################################################
#                                Group: Storage getters                                            #
####################################################################################################

# Function: getStorageType
sub getStorageType {
    my $this = shift;
    return $this->{storage_type};
}

# Function: getStorageRoot
sub getStorageRoot {
    my $this = shift;    
    if ($this->{storage_type} eq "FILE") {
        return $this->{data_path};
    }
    elsif ($this->{storage_type} eq "CEPH") {
        return $this->{data_pool};
    }
    elsif ($this->{storage_type} eq "S3") {
        return $this->{data_bucket};
    }
    elsif ($this->{storage_type} eq "SWIFT") {
        return $this->{data_container};
    }
}


# Function: setStorageRoot
sub setStorageRoot {
    my $this = shift;
    my $root = shift;

    if ($this->{storage_type} eq "FILE") {
        $this->{data_path} = $root;
    }
    elsif ($this->{storage_type} eq "CEPH") {
        $this->{data_pool} = $root;
    }
    elsif ($this->{storage_type} eq "S3") {
        $this->{data_bucket} = $root;
    }
    elsif ($this->{storage_type} eq "SWIFT") {
        $this->{data_container} = $root;
    }
}

# Function: getDataRoot
sub getDataRoot {
    my $this = shift;

    return File::Spec->catdir($this->getStorageRoot(), $this->{name});
}

### FILE

# Function: getDataDir
sub getDataDir {
    my $this = shift;    
    return $this->{data_path};
}

# Function: getDirDepth
sub getDirDepth {
    my $this = shift;
    return $this->{dir_depth};
}

### S3

# Function: getDataBucket
sub getDataBucket {
    my $this = shift;    
    return $this->{data_bucket};
}

### SWIFT

# Function: getDataContainer
sub getDataContainer {
    my $this = shift;    
    return $this->{data_container};
}

### CEPH

# Function: getDataPool
sub getDataPool {
    my $this = shift;    
    return $this->{data_pool};
}

####################################################################################################
#                                     Group: List tools                                            #
####################################################################################################

=begin nd
Function: loadList

Read the list and store content in an hash as following :
|   level => {
|       DATA => {
|          col_row => {
|              root => root, with pyramid name
|              name => slab name (type, level, column and row)
|              origin => full slab path, with the origin list format
|          }
|       },
|       MASK => {
|          col_row => {
|              root => root, with pyramid name
|              name => slab name (type, level, column and row)
|              origin => full slab path, with the origin list format
|          }
|       }
|   }
=cut
sub loadList {
    my $this = shift;

    if ($this->{cachedListModified}) {
        ERROR("Cached list have been modified, we don't erase this modification loading the list from the file");
        return FALSE;
    }

    if ($this->{listCached}) {
        DEBUG("List have already been loaded");
        return TRUE;
    }

    my $listPath = $this->getListPath();
    my $tmpList = sprintf "/tmp/content%08X.list", rand(0xffffffff);

    if (! ROK4::Core::ProxyStorage::copy($this->{storage_type}, $listPath, "FILE", $tmpList)) {
        ERROR("Cannot copy list file from final storage : $listPath");
        return FALSE;
    }

    # Pour pouvoir comprendre des anciennes listes
    my %objectTypeConverter = (
        DATA => "DATA",
        IMG => "DATA",
        IMAGE => "DATA"
    );

    if (! open LIST, "<", $tmpList) {
        ERROR("Cannot open pyramid list file (to load content in cache) : $tmpList");
        return FALSE;
    }

    # Lecture des racines
    my %roots;
    while( my $line = <LIST> ) {
        chomp $line;

        if ($line eq "#") {
            # separator between caches' roots and images
            last;
        }
        
        $line =~ s/\s+//g; # we remove all spaces
        my @tmp = split(/=/,$line,-1);
        
        if (scalar @tmp != 2) {
            ERROR(sprintf "Wrong formatted pyramid list (root definition) : %s",$line);
            return FALSE;
        }
        
        $roots{$tmp[0]} = $tmp[1];
    }

    while( my $line = <LIST> ) {
        chomp $line;

        # On isole la racine et le reste
        $line =~ m/^(\d+)\/.+/;
        my $index = $1;
        my $root = $roots{$index};
        my $target = $line;
        $target =~ s/^(\d+)\///;

        my $origin = "$root/$target";

        # On va vouloir déterminer le niveau, la colonne et la ligne de la dalle, ainsi que le type (DATA ou MASK)
        # Cette extraction diffère selon que l'on est en mode fichier ou objet

        my ($type, $level, $col, $row);

        # Cas fichier
        if ($this->getStorageType() eq "FILE") {
            # Cas fichier : $target = DATA/15/AB/CD/EF.tif
            my @parts = split("/", $target);
            # Dans le cas d'un stockage fichier, le premier élément du chemin est maintenant le type de donnée
            $type = $objectTypeConverter{shift(@parts)};
            # et le suivant est le niveau
            $level = shift(@parts);

            ($col,$row) = $this->{levels}->{$level}->getFromSlabPath($target);
        }
        # Cas objet
        else {
            # Cas objet : $target = DATATYPE_LEVEL_COL_ROW ou PYRAMIDNAME_DATATYPE_LEVEL_COL_ROW
            #                       Nouveau format            Ancien format

            my @p = split(/_/, $target);

            if (scalar(@p) == 4) {
                # Nouveau format
                $type = $p[0];
                $level = $p[1];
                $col = $p[2];
                $row = $p[3];
            } else {
                # Ancien format
                $row = pop(@p);
                $col = pop(@p);
                $level = pop(@p);
                $type = $objectTypeConverter{pop(@p)};
                my $pyrname = join("_", @p);

                # On repasse le nom de la pyramide vers la racine
                $root = "$root/$pyrname";
                $target = "${type}_${level}_${col}_${row}";
            }
        }
        
        if (exists $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"}) {
            WARN("The list contains twice the same slab : $type, $level, $col, $row");
        }
        $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"} = {
            root => $root,
            name => $target,
            origin => $origin
        }
    }

    close(LIST);

    $this->{listCached} = TRUE;

    return TRUE;
}


=begin nd
Function: getLevelsSlabs

Returns the cached list content for all levels.
=cut
sub getLevelsSlabs {
    my $this = shift;

    return $this->{cachedList};
} 

=begin nd
Function: getLevelSlabs

Returns the cached list content for one level.

Parameters (list):
    level - string - Identifiant of the asked level
=cut
sub getLevelSlabs {
    my $this = shift;
    my $level = shift;

    return $this->{cachedList}->{$level};
} 


=begin nd
Function: containSlab

Precises if the provided slab belongs to the pyramid, using the cached list. Returns the root and the name as a list reference if present, undef otherwise

Parameters (list):
    type - string - DATA
    level - string - Identifiant of the asked level
    col - integer - Column indice
    row - integer - Row indice
=cut
sub containSlab {
    my $this = shift;
    my $type = shift;
    my $level = shift;
    my $col = shift;
    my $row = shift;

    if (exists $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"}) {
        return [
            $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"}->{root},
            $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"}->{name}
        ];
    } else {
        return undef;
    }
} 


=begin nd
Function: modifySlab

Replace the full slab path with the local full path. This modification can be made persistent with <flushCachedList>.

Parameters (list):
    type - string - DATA
    level - string - Identifiant of the asked level
    col - integer - Column indice
    row - integer - Row indice
=cut
sub modifySlab {
    my $this = shift;
    my $type = shift;
    my $level = shift;
    my $col = shift;
    my $row = shift;

    if (! $this->{listCached}) {
        ERROR("We cannot modified cached list beacuse the list have not been loaded");
        return FALSE;
    }

    # La racine devient celle de la pyramide courante 
    $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"}->{root} = $this->getDataRoot();

    $this->{cachedListModified} = TRUE;

    # Mise à jour des limites
    $this->{levels}->{$level}->updateLimitsFromSlab($col, $row);

    return TRUE;
}


=begin nd
Function: deleteSlab

Delete the slab path from the cached list. This modification can be made persistent with <flushCachedList>.

Parameters (list):
    type - string - DATA
    level - string - Identifiant of the asked level
    col - integer - Column indice
    row - integer - Row indice
=cut
sub deleteSlab {
    my $this = shift;
    my $type = shift;
    my $level = shift;
    my $col = shift;
    my $row = shift;

    delete $this->{cachedList}->{$level}->{$type}->{"${col}_${row}"};

    return TRUE;
}


=begin nd
Function: flushCachedList

Save cached list in the original file. If no modification, do nothing.
=cut
sub flushCachedList {
    my $this = shift;

    if (! $this->{listCached}) {
        ERROR("We cannot flush an unloaded list");
        return FALSE;
    }

    if (! $this->{cachedListModified}) {
        WARN("The cached list have not been modified, it's useless to flush it");
        return TRUE;
    }

    my $tmpList = sprintf "/tmp/content%08X.list", rand(0xffffffff);
    if (! open LIST, ">", $tmpList) {
        ERROR("Cannot open temporary pyramid list file (to flush cached content) $tmpList");
        return FALSE;
    }

    my %roots;
    $roots{$this->getDataRoot()} = 0;

    foreach my $l (keys(%{$this->{cachedList}})) {
        # DATA
        while (my ($slabKey, $parts) = each(%{$this->{cachedList}->{$l}->{DATA}})) {

            my $root = $parts->{root};
            my $target = $parts->{name};

            my $rootInd;

            if (! exists $roots{$root}) {
                $rootInd = scalar(keys(%roots));
                $roots{$root} = $rootInd;
            } else {
                $rootInd = $roots{$root};
            }

            printf LIST "$rootInd/$target\n";
        }
    }

    close(LIST);

    # On va pouvoir écrire les racines maintenant
    my @LISTHDR;

    if (! tie @LISTHDR, 'Tie::File', $tmpList) {
        ERROR("Cannot flush the header of the cache list : $tmpList");
        return FALSE;
    }

    unshift @LISTHDR,"#\n";
    
    while ( my ($root,$rootInd) = each(%roots) ) {
        unshift @LISTHDR,(sprintf "%s=%s", $rootInd, $root);
    }
    
    untie @LISTHDR;

    $this->{cachedListModified} = FALSE;

    # Stockage à l'emplacement final
    my $listPath = $this->getListPath();

    if (! ROK4::Core::ProxyStorage::copy("FILE", $tmpList, $this->{storage_type}, $listPath)) {
        ERROR("Cannot copy list file to final storage : $listPath");
        return FALSE;
    }

    return TRUE;
}

=begin nd
Function: getCachedListStats

Prints the memory size of the cached list hash.
=cut
sub getCachedListStats {
    my $this = shift;

    my $nb = scalar(keys %{$this->{cachedList}});
    my $size = total_size($this->{cachedList});

    my $ret = "Stats :\n\t $size bytes\n";
    # $ret .= "\t $size bytes\n";
    # $ret .= sprintf "\t %s bytes per cached slab\n", $size / $nb;

    return $ret;
}


####################################################################################################
#                                   Group: Clone function                                          #
####################################################################################################

=begin nd
Function: clone

Clone object. Recursive clone only for levels. Other object attributes are just referenced.

Parameters (list):
    clone_name - string - Name of the cloned pyramid
    clone_root - string - Optionnal, storage directory or object tray of the cloned pyramid

Returns:
    the cloned pyramid
=cut
sub clone {
    my $this = shift;
    my $clone_name = shift;
    my $clone_root = shift;
    
    my $clone = { %{ $this } };
    bless($clone, 'ROK4::Core::PyramidVector');
    delete $clone->{levels};

    if (! defined $clone_root) {
        $clone_root = $this->getStorageRoot();
    } else {
        $clone->setStorageRoot($clone_root);
    }

    while (my ($id, $level) = each(%{$this->{levels}}) ) {
        $clone->{levels}->{$id} = $level->clone($clone_name, $clone_root);
    }

    $clone->{name} = $clone_name;

    return $clone;
}

1;
__END__
