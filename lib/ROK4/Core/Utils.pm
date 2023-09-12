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
#
################################################################################

=begin nd
File: Utils.pm

Class: ROK4::Core::Utils

(see libperlauto/ROK4_Core_Utils.png)
=cut

################################################################################

package ROK4::Core::Utils;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use JSON qw( );
use JSON::Validator;

################################################################################
# Constants
use constant TRUE  => 1;
use constant FALSE => 0;

####################################################################################################
#                                        Group: Maths                                              #
####################################################################################################

=begin nd
Function: isPositiveInt

Tests if the item is a positive base 10 integer (0 included).
Source : http://www.perlmonks.org/?node_id=614452

Parameters:
    item - number/string - the item to test

Returns:
    The boolean answer to the question.
=cut
sub isPositiveInt {
    my $item = shift;

    if ((isInteger($item)) && ($item >= 0)) {
        return TRUE;
    }
    return FALSE;
}

=begin nd
Function: isStrictPositiveInt

Tests if the item is a stricly positive base 10 integer.
Source : http://www.perlmonks.org/?node_id=614452

Parameters:
    item - number/string - the item to test

Returns:
    The boolean answer to the question.
=cut
sub isStrictPositiveInt {
    my $item = shift;

    if ((isInteger($item)) && ($item > 0)) {
        return TRUE;
    }
    return FALSE;
}

=begin nd
Function: isInteger

Tests if the item is a base 10 integer.

Parameters:
    item - number/string - the item to test

Returns:
    The boolean answer to the question.
=cut
sub isInteger {
    my $item = shift;

    if ($item =~ m/\A[+-]?[0-9]*[0-9][0-9]*\z/) {
        return TRUE;
    }
    return FALSE;
}

=begin nd
Function: isNumber

Tests if the item is a decimal number.

Parameters:
    item - number/string - the item to test

Returns:
    The boolean answer to the question.
=cut
sub isNumber {
    my $item = shift;

    if ($item =~ m/\A[+-]?[0-9]*[0-9][0-9]*[.]?[0-9]*\z/) {
        return TRUE;
    }
    return FALSE;
}

=begin nd
Function: isBbox

Tells if a string is a bouding box, i.e. a succession of coordinates in the form "xmin,ymin,xmax,ymax".

Parameters (list):
    value - string - String to test
=cut
sub isBbox {

    my $value = shift;

    my @array = split (',', $value);
    if (scalar @array == 4) {
        foreach my $item (@array) {
            if (! isNumber($item) ) {
                return FALSE;
            }
        }  
    } else {
        return FALSE;
    }

    if ($array[0] > $array[2] || $array[1] > $array[3]) {
        return FALSE;
    }

    return TRUE;
}


=begin nd
Function: isEmpty

Precises if an hash or a reference can be considered as empty.

Parameters (list):
    value - var - Variable to test
=cut
sub isEmpty {

  my $value = shift;
  
  return FALSE if (ref($value) eq "HASH");
  return TRUE  if (! defined $value);
  return TRUE  if ($value eq "");
  return FALSE;
}

####################################################################################################
#                                 Group: JSON methods                                              #
####################################################################################################

=begin nd
Function: get_hash_from_json_file

Parameters (list):
    file - string - Path to JSON file to load
    
Examples:
    - IGN::Utils::get_hash_from_json_file("/home/toto/file.json")

Returns:
    Hash reference if success, undef if failure

=cut

sub get_hash_from_json_file {
    my $file = shift;

    my $json_text = do {
        open(my $json_fh, "<", $file) or do {
            ERROR(  sprintf "Cannot open JSON file : %s (%s)", $file, $! );
            return undef;
        };
        local $/;
        <$json_fh>
    };
    
    return JSON::from_json($json_text);
}

=begin nd
Function: validate_hash_with_json_schema

Parameters (list):
    data - hash reference - content to validate
    schema - hash reference - JSON schema

Returns:
    TRUE or FALSE

=cut

sub validate_hash_with_json_schema {
    my $data = shift;
    my $schema = shift;

    my $jv = JSON::Validator->new();
    $jv->schema($schema);
    my @errors = $jv->validate($data);
    
    if (scalar @errors > 0) {
        for my $e (@errors) {
            ERROR("    $e");
        }
        return FALSE;
    }
    
    return TRUE;
}

1;