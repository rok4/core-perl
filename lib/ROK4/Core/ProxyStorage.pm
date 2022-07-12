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
File: ProxyStorage.pm

Class: ROK4::Core::ProxyStorage

(see libperlauto/ROK4_Core_ProxyStorage.png)

Proxy to manipulate different storage types : object or file, we can copy, reference or remove from one to another.

In SWIFT case, actions required a prior authentication. The token is requested with the first action.
If an action is unauthorized during de processing, we retry once with a new token

Using:
    (start code)
    use ROK4::Core::ProxyStorage;
    (end code)
=cut

################################################################################

package ROK4::Core::ProxyStorage;

use strict;
use warnings;

use Data::Dumper;
use Digest::SHA;
use Net::Amazon::S3;
use File::Basename;
use File::Copy ();
use File::Map qw(map_file);
use File::Path;
use File::Spec::Link;
use HTTP::Request::Common;
use HTTP::Request;
use HTTP::Response;
use JSON;
use LWP::UserAgent;


use Log::Log4perl qw(:easy);

################################################################################
# Constantes
use constant TRUE  => 1;
use constant FALSE => 0;

use constant ROK4_IMAGE_HEADER_SIZE => 2048;

# Signature d'un objet CEPH LIEN et sa taille
use constant ROK4_SYMLINK_SIGNATURE_SIZE => 8;
use constant ROK4_SYMLINK_SIGNATURE => "SYMLINK#";

my @STORAGETYPES = ("FILE", "CEPH", "S3", "SWIFT");

### User agent for HTTP(S) requests
my $UA = undef;
### SWIFT token, without the header name
my $SWIFT_TOKEN = undef;

### S3
my $S3_HOST = undef;
my $S3_SECURE = 1;
my $S3 = undef;

####################################################################################################
#                             Group: Controls methods                                              #
####################################################################################################

=begin nd
Function: checkEnvironmentVariables

Return TRUE if all required environment variables for storage are defined FALSE otherwise
=cut
sub checkEnvironmentVariables {
    my $type = shift;
    if ($type eq "CEPH") {

        if (! defined $ENV{ROK4_CEPH_CONFFILE}) {
            ERROR("Environment variable ROK4_CEPH_CONFFILE is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_CEPH_USERNAME}) {
            ERROR("Environment variable ROK4_CEPH_USERNAME is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_CEPH_CLUSTERNAME}) {
            ERROR("Environment variable ROK4_CEPH_CLUSTERNAME is not defined");
            return FALSE;
        }
        
    } elsif ($type eq "SWIFT") {

        if (! defined $ENV{ROK4_SWIFT_AUTHURL}) {
            ERROR("Environment variable ROK4_SWIFT_AUTHURL is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_SWIFT_USER}) {
            ERROR("Environment variable ROK4_SWIFT_USER is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_SWIFT_PASSWD}) {
            ERROR("Environment variable ROK4_SWIFT_PASSWD is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_SWIFT_PUBLICURL}) {
            ERROR("Environment variable ROK4_SWIFT_PUBLICURL is not defined");
            return FALSE;
        }

        if (defined $ENV{ROK4_KEYSTONE_DOMAINID}) {
            if (! defined $ENV{ROK4_KEYSTONE_PROJECTID}) {
                ERROR("Environment variable ROK4_KEYSTONE_PROJECTID is not defined");
                ERROR("We need it for a keystone authentication (swift)");
                return FALSE;
            }
        } else {
            
            if (! defined $ENV{ROK4_SWIFT_ACCOUNT}) {
                ERROR("Environment variable ROK4_SWIFT_ACCOUNT is not defined");
                ERROR("We need it for a swift authentication");
                return FALSE;
            }
        }

    } elsif ($type eq "S3") {
        
        if (! defined $ENV{ROK4_S3_URL}) {
            ERROR("Environment variable ROK4_S3_URL is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_S3_KEY}) {
            ERROR("Environment variable ROK4_S3_KEY is not defined");
            return FALSE;
        }
        if (! defined $ENV{ROK4_S3_SECRETKEY}) {
            ERROR("Environment variable ROK4_S3_SECRETKEY is not defined");
            return FALSE;
        }

        $S3_HOST = $ENV{ROK4_S3_URL};
        if ($S3_HOST =~ m/^http:\/\//) {
            $S3_SECURE = 0;
            $S3_HOST =~ s/^http:\/\///;
        } else {
            $S3_HOST =~ s/^https:\/\///;
        }

        $S3 = Net::Amazon::S3->new (
            secure => $S3_SECURE,
            aws_access_key_id => $ENV{ROK4_S3_KEY},
            aws_secret_access_key => $ENV{ROK4_S3_SECRETKEY},
            host => $S3_HOST,
            secure => $S3_SECURE
        );
    }

    return TRUE;
}



####################################################################################################
#                               Group: Copy methods                                                #
####################################################################################################

=begin nd
Function: copy

Return TRUE if success FALSE otherwise

When the source object to copy is a symbolic object, we copy the link's target (the real object), to have the file's behavior.
=cut
sub copy {
    my $fromType = shift;
    my $fromPath = shift;
    my $toType = shift;
    my $toPath = shift;

    DEBUG("Copying from '$fromType' path '$fromPath', to '$toType' path '$toPath'.");

    if ($fromType eq "FILE") { ############################################ FILE
        if ($toType eq "FILE") {
            # File -> File

            # create folder
            my $dir = File::Basename::dirname($toPath);
            my $errors_list;
            File::Path::make_path($dir, {error => \$errors_list});
            if (defined($errors_list) && scalar(@{$errors_list})) {
                ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
                return FALSE;
            }
        
            my $err_bool = 0;
            my $err_message = '';
            File::Copy::copy("$fromPath", "$toPath") or ($err_bool, $err_message) = (1, $!);
            if ($err_bool) {
                ERROR("Cannot copy from file '$fromPath' to file '$toPath' : $err_message");
                return FALSE;
            }
            return TRUE;
        }
        elsif ($toType eq "CEPH") {
            # File -> Ceph

            my ($poolName, @rest) = split("/", $toPath);
            my $objectName = join("/", @rest);

            if (! defined $poolName || ! defined $objectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $toPath");
                return FALSE;
            }

            if (system("rados -p $poolName put $objectName $fromPath") == 0) {
                return TRUE;
            } else {
                ERROR("Cannot upload file '$fromPath' to CEPH object $objectName (pool $poolName): $!");
                return FALSE;
            }
        }
        elsif ($toType eq "S3") {
            # File -> S3

            my ($bucketName, @rest) = split("/", $toPath);
            my $objectName = join("/", @rest);

            if (! defined $bucketName || ! defined $objectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $toPath");
                return FALSE;
            }

            if (! -e $fromPath) {
                ERROR("File $fromPath to upload to s3 does not exist");
                return FALSE;
            }

            my $bucket = $S3->bucket($bucketName);
            # À ce stade le bucket peut ne pas exister

            my $result = $bucket->add_key_filename($objectName, $fromPath);
            if (! defined $result) {
                ERROR("Cannot upload file '$fromPath' to S3 object $objectName (bucket $bucketName)");
                return FALSE;
            }
            return TRUE;
        }
        elsif ($toType eq "SWIFT") {
            # File -> Swift
            my ($containerName, @rest) = split("/", $toPath);
            my $objectName = join("/", @rest);

            if (! defined $containerName || ! defined $objectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $resource = "/$containerName/$objectName";

            my $body;
            map_file $body, $fromPath;
            
            my $request = HTTP::Request->new(PUT => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);
            $request->content($body);

            my $try = 1;
            while ($try <= 2) {
                $request->header('X-Auth-Token' => _getSwiftToken());

                my $response = _getUserAgent()->request($request);
                if ($response->is_success) {
                    return TRUE;
                }
                elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                    DEBUG("Authentication may have expired. Reconnecting...");
                    if (! defined _getSwiftToken(TRUE)) {
                        ERROR("Reconnection attempt failed.");
                        return undef;
                    }
                    DEBUG("Successfully reconnected.");
                    $try++;
                }
                else {
                    ERROR("Cannot upload SWIFT object '$toPath' from file $fromPath");
                    ERROR("HTTP code: ", $response->code);
                    ERROR("HTTP message: ", $response->message);
                    ERROR("HTTP decoded content : ", $response->decoded_content);
                    return FALSE;
                }
            }            
        }
    }
    elsif ($fromType eq "CEPH") { ############################################ CEPH
        if ($toType eq "FILE") {
            # Ceph -> File

            my ($poolName, @rest) = split("/", $fromPath);
            my $objectName = join("/", @rest);

            if (! defined $poolName || ! defined $objectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $fromPath");
                return FALSE;
            }

            # create folder
            my $dir = File::Basename::dirname($toPath);
            my $errors_list;
            File::Path::make_path($dir, {error => \$errors_list});
            if (defined($errors_list) && scalar(@{$errors_list})) {
                ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
                return FALSE;
            }

            if (system("rados -p $poolName get $objectName $toPath") == 0) {
                return TRUE;
            } else {
                ERROR("Cannot download CEPH object $fromPath into file '$toPath': $@");
                return FALSE;
            }
        }
        elsif ($toType eq "CEPH") {
            # Ceph -> Ceph

            my ($fromPool, @from) = split("/", $fromPath);
            my $fromObjectName = join("/", @from);

            if (! defined $fromPool || ! defined $fromObjectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toPool, @to) = split("/", $toPath);
            my $toObjectName = join("/", @to);

            if (! defined $toPool || ! defined $toObjectName) {
                ERROR("CEPH path is not valid (<poolName>/<objectName>) : $toPath");
                return FALSE;
            }

            if ($toPool ne $fromPool) {
                ERROR("CEPH copy is not possible for different pool: $fromPath -> X $toPath");
                return FALSE;
            }

            if (system("rados -p $toPool cp $fromObjectName $toObjectName") == 0) {
                return TRUE;
            } else {
                ERROR("Cannot copy CEPH object $fromObjectName -> $toObjectName (pool $fromPool): $!");
                return FALSE;
            }
        }
    }
    elsif ($fromType eq "S3") { ############################################ S3

        if ($toType eq "FILE") {
            # S3 -> File

            my ($bucketName, @rest) = split("/", $fromPath);
            my $objectName = join("/", @rest);

            if (! defined $bucketName || ! defined $objectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $bucket = $S3->bucket($bucketName);
            # À ce stade le bucket peut ne pas exister

            # create folder
            my $dir = File::Basename::dirname($toPath);
            my $errors_list;
            File::Path::make_path($dir, {error => \$errors_list});
            if (defined($errors_list) && scalar(@{$errors_list})) {
                ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
                return FALSE;
            }

            my $result = $bucket->get_key_filename($objectName, "GET", $toPath);
            if (! defined $result) {
                ERROR("Cannot download S3 object '$fromPath' to file $toPath");
                return FALSE;
            } 
            return TRUE;
        }
        elsif ($toType eq "S3") {
            # S3 -> S3

            my ($fromBucket, @from) = split("/", $fromPath);
            my $fromObjectName = join("/", @from);

            if (! defined $fromBucket || ! defined $fromObjectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toBucket, @to) = split("/", $toPath);
            my $toObjectName = join("/", @to);

            if (! defined $toBucket || ! defined $toObjectName) {
                ERROR("S3 path is not valid (<bucketName>/<objectName>) : $toPath");
                return FALSE;
            }

            my $resource = "/$toBucket/$toObjectName";
            my $content_type = "application/octet-stream";
            my $date_gmt = qx(TZ=GMT date -R);
            chomp($date_gmt);
            my $string_to_sign="PUT\n\n$content_type\n$date_gmt\nx-amz-copy-source:/$fromBucket/$fromObjectName\n$resource";

            my $signature = Digest::SHA::hmac_sha1_base64($string_to_sign, $ENV{ROK4_S3_SECRETKEY});
            while (length($signature) % 4) {
                $signature .= '=';
            }

            my $request = HTTP::Request->new(PUT => $ENV{ROK4_S3_URL}.$resource);

            $request->header('Host' => $S3_HOST);
            $request->header('Date' => $date_gmt);
            $request->header('Content-Type' => $content_type);
            $request->header('x-amz-copy-source' => "/$fromBucket/$fromObjectName");
            $request->header('Authorization' => sprintf ("AWS %s:$signature", $ENV{ROK4_S3_KEY}));

            my $response = _getUserAgent()->request($request, $toPath);
            if ($response->is_success) {
                return TRUE;
            } else {
                ERROR("Cannot copy S3 object '$fromPath' to S3 object '$toPath'");
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
    }
    elsif ($fromType eq "SWIFT") { ############################################ SWIFT

        if ($toType eq "FILE") {
            # Swift -> File

            my ($containerName, @rest) = split("/", $fromPath);
            my $objectName = join("/", @rest);

            if (! defined $containerName || ! defined $objectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my $resource = "/$containerName/$objectName";

            my $request = HTTP::Request->new(GET => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);
            
            # create folder
            my $dir = File::Basename::dirname($toPath);
            my $errors_list;
            File::Path::make_path($dir, {error => \$errors_list});
            if (defined($errors_list) && scalar(@{$errors_list})) {
                ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
                return FALSE;
            }

            my $try = 1;
            while ($try <= 2) {
                $request->header('X-Auth-Token' => _getSwiftToken());

                my $response = _getUserAgent()->request($request, $toPath);
                if ($response->is_success) {
                    return $response->header("Content-Length");
                }
                elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                    DEBUG("Authentication may have expired. Reconnecting...");
                    if (! defined _getSwiftToken(TRUE)) {
                        ERROR("Reconnection attempt failed.");
                        return FALSE;
                    }
                    DEBUG("Successfully reconnected.");
                    $try++;
                }
                else {
                    ERROR("Cannot download SWIFT object '$fromPath' to file $toPath");
                    ERROR("HTTP code: ", $response->code);
                    ERROR("HTTP message: ", $response->message);
                    ERROR("HTTP decoded content : ", $response->decoded_content);
                    return FALSE;
                }
            }
        }
        elsif ($toType eq "SWIFT") {
            # Swift -> Swift

            my ($fromContainer, @from) = split("/", $fromPath);
            my $fromObjectName = join("/", @from);

            if (! defined $fromContainer || ! defined $fromObjectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $fromPath");
                return FALSE;
            }

            my ($toContainer, @to) = split("/", $toPath);
            my $toObjectName = join("/", @to);

            if (! defined $toContainer || ! defined $toObjectName) {
                ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $toPath");
                return FALSE;
            }

            my $resource = "/$fromContainer/$fromObjectName";

            my $request = HTTP::Request->new(COPY => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);
            $request->header('Destination' => "$toContainer/$toObjectName");

            my $try = 1;
            while ($try <= 2) {
                $request->header('X-Auth-Token' => _getSwiftToken());

                my $response = _getUserAgent()->request($request);
                if ($response->is_success) {
                    return TRUE;
                }
                elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                    DEBUG("Authentication may have expired. Reconnecting...");
                    if (! defined _getSwiftToken(TRUE)) {
                        ERROR("Reconnection attempt failed.");
                        return FALSE;
                    }
                    DEBUG("Successfully reconnected.");
                    $try++;
                }
                else {
                    ERROR("Cannot copy SWIFT object : '$fromPath' -> '$toPath'");
                    ERROR("HTTP code: ", $response->code);
                    ERROR("HTTP message: ", $response->message);
                    ERROR("HTTP decoded content : ", $response->decoded_content);
                    return FALSE;
                }
            }            
        }
    }

    ERROR("copy $fromType : $fromPath -> $toType : $toPath not implemented.");   
    return FALSE;
}

####################################################################################################
#                               Group: Read methods                                                #
####################################################################################################

=begin nd
Function: getData

Return binary data as string
=cut
sub getData {
    my $type = shift;
    my $path = shift;
    my $offset = shift;
    my $size = shift;

    if ($type eq "FILE") {
        open(IN, '<:raw', $path) or do {
            ERROR("Cannot open $path : $!");
            return (undef, undef);
        };

        if (defined $size && defined $offset) {
            seek(IN, $offset, 0);
            my $data;
            my $read = read(IN, $data, $size);
            if (! defined $read) {
                ERROR("Cannot read $path ($size bytes from $offset)");
                return (undef, undef);
            }
            close(IN);
            if ($read == 0) {
                # Nous avons lu tout l'objet, mais la taille lue est celle demandée
                return ($size, $data);
            } else {
                return ($read, $data);
            }
        } else {
            my @datarray = <IN>;
            my $data = join('', @datarray);
            my $length = length( $data );
            close(IN);
            return ($length, $data);
        }


    }
    elsif ($type eq "CEPH") {
        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return (undef, undef);
        }

        if (defined $size && defined $offset) {
            ERROR("CEPH partial read not implemented");
            return (undef, undef);
        }

        my $data = qx(rados -p $poolName get $objectName /dev/stdout);
        chomp $data;
        return (length( $data ), $data);

    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return (undef, undef);
        }

        if (defined $size && defined $offset) {
            ERROR("S3 partial read not implemented");
            return (undef, undef);
        }

        my $bucket = $S3->bucket($bucketName);
        # À ce stade le bucket peut ne pas exister

        my $data = $bucket->get_key($objectName, "GET");
        if (! defined $data) {
            ERROR("Cannot download S3 object '$bucketName / $objectName' content");
            return (undef, undef);
        }
        return ( $data->{7181} , $data->{value});
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return (undef, undef);
        }

        my $resource = "/$containerName/$objectName";

        my $request = HTTP::Request->new(GET => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);

        if (defined $size && defined $offset) {
            $request->header('Range' => sprintf("$offset-%s", $offset + $size - 1));
        }

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                my $data = $response->content;
                chomp $data;
                return (length( $data ), $data);
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return (undef, undef);
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return (undef, undef);
            }
        }
    } else {
        ERROR("getData $type not implemented.");  
    }

    return undef;
}


####################################################################################################
#                               Group: Write methods                                               #
####################################################################################################

=begin nd
Function: setData

Write binary data as string
=cut
sub setData {
    my $type = shift;
    my $path = shift;
    my $data = shift;

    if ($type eq "FILE") {

        my $dir = File::Basename::dirname($path);
        if (! -d $dir) {
            eval { mkpath([$dir]); };
            if ($@) {
                ERROR(sprintf "Can not create the directory '%s' : %s !", $dir, $@);
                return FALSE;
            }
        }

        open(OUT, '>:raw', $path) or do {
            ERROR("Cannot open $path : $!");
            return FALSE;
        };

        print OUT $data;
        close(OUT);
        return TRUE;
    }
    elsif ($type eq "CEPH") {
        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return FALSE;
        }

        if (system("echo -n \"$data\" | rados -p $poolName put $objectName /dev/stdin") != 0) {
            ERROR("Cannot write to CEPH $poolName / $objectName : $!");
            return FALSE;
        }
        return TRUE;

    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return (undef, undef);
        }

        my $bucket = $S3->bucket($bucketName);
        # À ce stade le bucket peut ne pas exister

        my $ok = $bucket->add_key($objectName, $data);
        if (! $ok) {
            ERROR("Cannot upload S3 object '$bucketName / $objectName' content");
            return FALSE;
        } 
        return TRUE;
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return FALSE;
        }

        my $resource = "/$containerName/$objectName";

        my $request = HTTP::Request->new(PUT => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);
        $request->content($data);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                return TRUE;
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return FALSE;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
    } else {
        ERROR("setData $type not implemented.");  
    }

}

####################################################################################################
#                               Group: Test methods                                                #
####################################################################################################

=begin nd
Function: isPresent

Return TRUE or FALSE
=cut
sub isPresent {
    my $type = shift;
    my $path = shift;

    DEBUG(sprintf "$type $path exists ?");

    if ($type eq "FILE") {
        if (-f $path) {
            return TRUE;
        }
        if (-d $path) {
            return TRUE;
        }

        return FALSE;
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return FALSE;
        }

        if (system("rados -p $poolName stat $objectName 1>/dev/null 2>/dev/null") == 0) {
            return TRUE;
        } else {
            return FALSE;
        }
    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return FALSE;
        }

        my $result = $S3->list_bucket({
            bucket => $bucketName,
            prefix => $objectName
        });

        if (scalar(@{$result->{keys}} == 0)) {
            return FALSE;
        } else {
            return TRUE;
        }
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return FALSE;
        }

        my $resource = "/$containerName/$objectName";

        my $request = HTTP::Request->new(HEAD => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                return TRUE;
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return FALSE;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                return FALSE;
            }
        }
    }

    return FALSE;
}

####################################################################################################
#                               Group: Content methods                                             #
####################################################################################################

=begin nd
Function: getSize

Return size of file/object
=cut
sub getSize {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {
        return -s $path;
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $containerName || ! defined $objectName) {
            ERROR("SWIFT path is not valid (<containerName>/<objectName>) : $path");
            return undef;
        }

        my $resource = "/$containerName/$objectName";

        my $request = HTTP::Request->new(HEAD => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                return $response->header("Content-Length");
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return undef;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return undef;
            }
        }
    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return undef;
        }

        my $result = $S3->list_bucket({
            bucket => $bucketName,
            prefix => $objectName
        });

        if (scalar(@{$result->{keys}} == 0)) {
            ERROR("Cannot stat S3 object $objectName (bucket $bucketName)");
            return undef;
        }

        return $result->{keys}->[0]->{size};
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return undef;
        }

        my $ret = qx(rados -p $poolName stat $objectName);
        if ($@) {
            ERROR("Cannot stat CEPH object $objectName (pool $poolName): $!");
            return undef;
        }
        chomp($ret);

        return (split(/ /, $ret))[-1];
    }

    return undef;
}

####################################################################################################
#                               Group: Delete methods                                              #
####################################################################################################

=begin nd
Function: remove

Remove the file/object provided
=cut
sub remove {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {
        if (system("rm -r $path") == 0) {
            return TRUE;
        }
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (system("rados -p $poolName rm $objectName") == 0) {
            return TRUE;
        }
    }
    elsif ($type eq "SWIFT") {

        my ($containerName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        my $resource = "/$containerName/$objectName";

        my $request = HTTP::Request->new(DELETE => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                return TRUE;
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return FALSE;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return FALSE;
            }
        }
    }
    elsif ($type eq "S3") {

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return FALSE;
        }

        my $resource = "/$bucketName/$objectName";
        my $contentType="application/octet-stream";
        my $dateValue=qx(TZ=GMT date -R);
        chomp($dateValue);
        my $stringToSign="DELETE\n\n$contentType\n$dateValue\n$resource";

        my $signature = Digest::SHA::hmac_sha1_base64($stringToSign, $ENV{ROK4_S3_SECRETKEY});
        while (length($signature) % 4) {
            $signature .= '=';
        }

        my $host = $ENV{ROK4_S3_URL};
        $host =~ s/^https?:\/\/(.+):[0-9]+\/?$/$1/;

        # set custom HTTP request header fields
        my $request = HTTP::Request->new(DELETE => $ENV{ROK4_S3_URL}.$resource);
        $request->header('Host' => $host);
        $request->header('Date' => $dateValue);
        $request->header('Content-Type' => $contentType);
        $request->header('Authorization' => sprintf ("AWS %s:$signature", $ENV{ROK4_S3_KEY}));
         
        my $response = _getUserAgent()->request($request);
        if ($response->is_success) {
            return TRUE;
        }
        else {
            ERROR("HTTP code: ", $response->code);
            ERROR("HTTP message: ", $response->message);
            ERROR("HTTP decoded content : ", $response->decoded_content);
            return FALSE;
        }
    }

    return FALSE;
}

####################################################################################################
#                               Group: Link methods                                                #
####################################################################################################

=begin nd
Function: symLink

Return the real file/object linked if success, undef otherwise
=cut
sub symLink {
    my $targetType = shift;
    my $targetPath = shift;
    my $toType = shift;
    my $toPath = shift;

    DEBUG("Symlink target '$targetType' path '$targetPath', link '$toType' path '$toPath'.");

    if ($targetType eq "FILE" && $toType eq "FILE") {        

        # create folder
        my $dir = File::Basename::dirname($toPath);
        my $errors_list;
        File::Path::make_path($dir, {error => \$errors_list});
        if (defined($errors_list) && scalar(@{$errors_list})) {
            ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
            return FALSE;
        }

        my $relativeTargetPath = File::Spec->abs2rel($targetPath,$dir);

        if (! symlink ($relativeTargetPath, $toPath)) {
            ERROR (sprintf "The file '%s' can not be linked by '%s' (%s) ?", $targetPath, $toPath, $!);
            return undef;
        }

        return $targetPath;
    }
    elsif ($targetType eq "CEPH" && $toType eq "CEPH") {

        my ($toPoolName, @rest) = split("/", $toPath);
        $toPath = join("/", @rest);

        my $symlink_content = ROK4_SYMLINK_SIGNATURE . $targetPath;
        if (system("echo -n \"$symlink_content\" | rados -p $toPoolName put $toPath /dev/stdin") == 0) {
            return "$targetPath";
        } else {
            ERROR("Cannot symlink (make a rados put) object $targetPath with alias $toPath : $@");
            return undef;
        }

    }
    elsif ($targetType eq "S3" && $toType eq "S3") {

        my $symlink_content = ROK4_SYMLINK_SIGNATURE . $targetPath;

        my ($toBucketName, @rest) = split("/", $toPath);
        $toPath = join("/", @rest);

        my $bucket = $S3->bucket($toBucketName);

        my $ok = $bucket->add_key($toPath, $symlink_content);
        if (! $ok) {
            ERROR("Cannot upload S3 object '$toBucketName / $toPath' content");
            return undef;
        } 
        return $targetPath;
    }
    elsif ($targetType eq "SWIFT" && $toType eq "SWIFT") {

        my $symlink_content = ROK4_SYMLINK_SIGNATURE . $targetPath;

        my $resource = "/$toPath";

        my $request = HTTP::Request->new(PUT => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);
        $request->content($symlink_content);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                return "$targetPath";
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return undef;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return undef;
            }
        }
    }

    ERROR("Symbolic linking can only be done between two file/path using the same storage type (and not $toType -> $targetType)");
    return undef;
}

=begin nd
Function: hardLink

Return TRUE if success FALSE otherwise
=cut
sub hardLink {
    my $targetType = shift;
    my $targetPath = shift;
    my $toType = shift;
    my $toPath = shift;

    if ($targetType eq "FILE" && $toType eq "FILE") {

        # create folder
        my $dir = File::Basename::dirname($toPath);
        my $errors_list;
        File::Path::make_path($dir, {error => \$errors_list});
        if (defined($errors_list) && scalar(@{$errors_list})) {
            ERROR("Cannot create directory '$dir' : ", $$errors_list[0]{$dir});
            return FALSE;
        }

        my $realTarget;
        if (-f $targetPath && ! -l $targetPath) {
            $realTarget = $targetPath;
        }
        elsif (-f $targetPath && -l $targetPath) {
            $realTarget = File::Spec::Link->full_resolve( File::Spec::Link->linked($targetPath) );
        } else {
            ERROR(sprintf "The file (to hardlink) '%s' is not a file or a link in '%s' !", basename($targetPath), dirname($targetPath));
            return FALSE;
        }

        if (! link($realTarget, $toPath)) {
            ERROR("Cannot link (hard) file $targetPath from file $toPath : $!");
            return FALSE;
        }

        return TRUE;
    }

    ERROR("Hard linking can only be done between two files (and not $toType -> $targetType)");
    return FALSE;
}

####################################################################################################
#                              Group: Getters functions                                            #
####################################################################################################

=begin nd
Function: isSwiftKeystoneAuthentication

Precise if swift authentication is made with keystone
=cut
sub isSwiftKeystoneAuthentication {
    if (defined $ENV{ROK4_KEYSTONE_DOMAINID}) {
        return TRUE;
    }
    return FALSE;
};


####################################################################################################
#                              Group: Internal functions                                           #
####################################################################################################

=begin nd
Function: _getSwiftToken

Get the swift token. If token is undefined or if we force authentication, new token is requested

Parameters:
    force - boolean - Do we force to authenticate again. FALSE by default

=cut
sub _getSwiftToken {
    my $force = shift;

    if (! defined $force) {
        $force = FALSE;
    }

    if (! $force && defined $SWIFT_TOKEN) {
        return $SWIFT_TOKEN;
    }

    if (defined $ENV{ROK4_KEYSTONE_DOMAINID}) {
        # Keystone authentication
        my $body_object = {
            "auth" => {
                "scope" => {
                    "project" => {
                        "id" => $ENV{ROK4_KEYSTONE_PROJECTID}
                    }
                },
                "identity" => {
                    "methods" => [
                        "password"
                    ],
                    "password" => {
                        "user" => {
                            "domain" => {
                                "id" => $ENV{ROK4_KEYSTONE_DOMAINID}
                            },
                            "name" => $ENV{ROK4_SWIFT_USER},
                            "password" => $ENV{ROK4_SWIFT_PASSWD}
                        }
                    }
                }
            }
        };
        my $json = JSON::to_json($body_object, {utf8 => 1});

        my $request = HTTP::Request::Common::POST(
            $ENV{ROK4_SWIFT_AUTHURL},
            Content_Type => "application/json",
            Content => $json
        );

        my $response = _getUserAgent()->request($request);

        if (! defined $response || ! $response->is_success() ) {
            ERROR("Cannot get Swift token via Keystone");
            ERROR(Dumper($response));
            return undef;
        }

        $SWIFT_TOKEN = $response->header("X-Subject-Token");
        if (! defined $SWIFT_TOKEN) {
            ERROR("No token in the Keystone authentication response");
            ERROR(Dumper($response));
        }
        
    } else {
        # Native swift authentication
        my $request = HTTP::Request::Common::GET(
            $ENV{ROK4_SWIFT_AUTHURL}
        );

        $request->header(
            'X-Storage-User' => $ENV{ROK4_SWIFT_ACCOUNT}.":".$ENV{ROK4_SWIFT_USER},
            'X-Storage-Pass' => $ENV{ROK4_SWIFT_PASSWD},
            'X-Auth-User' => $ENV{ROK4_SWIFT_ACCOUNT}.":".$ENV{ROK4_SWIFT_USER},
            'X-Auth-Key' => $ENV{ROK4_SWIFT_PASSWD}
        );

        my $response = _getUserAgent()->request($request);

        if (! defined $response || ! $response->is_success() ) {
            ERROR("Cannot get Swift token");
            return undef;
        }

        $SWIFT_TOKEN = $response->header("X-Auth-Token");
        if (! defined $SWIFT_TOKEN) {
            ERROR("No token in the swift authentication response");
            ERROR(Dumper($response));
        }
    }

    return $SWIFT_TOKEN; 
};

=begin nd
Function: _getUserAgent

Get the user agent to use to request REST storages. Create it if undefined.
=cut
sub _getUserAgent {
    if (! defined $UA) {
        $UA = LWP::UserAgent->new();
        if (defined $ENV{ROK4_SSL_NO_VERIFY}) {
            $UA->ssl_opts(verify_hostname => 0);
        }
        if (defined $ENV{HTTP_PROXY}) {
            $UA->proxy('http', $ENV{HTTP_PROXY});
        }
        if (defined $ENV{HTTPS_PROXY}) {
            $UA->proxy('https', $ENV{HTTPS_PROXY});
        }
        if (defined $ENV{NO_PROXY}) {
            $UA->no_proxy(split(/,/, $ENV{NO_PROXY}));
        }
    }
    return $UA;
};


=begin nd
Function: _getRealData

Return the target if file/object is a symbolic file/object, and return the provided file/object if real. Return undef if file/object does not exist.
=cut
sub _getRealData {
    my $type = shift;
    my $path = shift;

    if ($type eq "FILE") {

        if (! -e $path) {
            return undef;
        }
        elsif (-f $path && ! -l $path) {
            return $path;
        }
        elsif (-f $path && -l $path) {
            my $realTarget = File::Spec::Link->full_resolve( File::Spec::Link->linked($path) );
            return $realTarget;
        }
    }
    elsif ($type eq "CEPH") {

        my ($poolName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $poolName || ! defined $objectName) {
            ERROR("CEPH path is not valid (<poolName>/<objectName>) : $path");
            return undef;
        }

        my $value = getSize("CEPH",$path);

        if ( ! defined $value ) {
            return undef;
        }

        if ( $value < ROK4_IMAGE_HEADER_SIZE ) {

            my $realTarget = qx(rados -p $poolName get $objectName /dev/stdout);
            chomp $realTarget;
            
            if (index($realTarget, ROK4_SYMLINK_SIGNATURE) == -1) {
                # L'objet est petit mais ne commence pas par la signature des objets symboliques
                return $path;
            }

            return substr $realTarget, ROK4_SYMLINK_SIGNATURE_SIZE;

        } else {
            return $path;
        }
    }
    elsif ($type eq "S3") {

        my $value = getSize("S3",$path);

        if ( ! defined $value ) {
            return undef;
        }

        if ( $value >= ROK4_IMAGE_HEADER_SIZE ) {
            return $path;
        }

        my ($bucketName, @rest) = split("/", $path);
        my $objectName = join("/", @rest);

        if (! defined $bucketName || ! defined $objectName) {
            ERROR("S3 path is not valid (<bucketName>/<objectName>) : $path");
            return undef;
        }

        my $bucket = $S3->bucket($bucketName);

        my $result = $bucket->get_key($objectName);
        if (! defined $result) {
            ERROR("Cannot get S3 object '$bucketName / $objectName' content");
            return undef;
        }

        if (index($result->{value}, ROK4_SYMLINK_SIGNATURE) == -1) {
            # L'objet est petit mais ne commence pas par la signature des objets symboliques
            return $path;
        }

        return substr $result->{value}, ROK4_SYMLINK_SIGNATURE_SIZE;
    }
    elsif ($type eq "SWIFT") {

        my $value = getSize("SWIFT",$path);

        if ( ! defined $value ) {
            return undef;
        }

        if ( $value >= ROK4_IMAGE_HEADER_SIZE ) {
            return $path;
        }

        my $resource = "/$path";

        my $request = HTTP::Request->new(GET => $ENV{ROK4_SWIFT_PUBLICURL}.$resource);

        my $try = 1;
        while ($try <= 2) {
            $request->header('X-Auth-Token' => _getSwiftToken());

            my $response = _getUserAgent()->request($request);
            if ($response->is_success) {
                my $linkContent = $response->content;
                chomp $linkContent;
                if (index($linkContent, ROK4_SYMLINK_SIGNATURE) == -1) {
                    # L'objet est petit mais ne commence pas par la signature des objets symboliques
                    return $path;
                }

                return substr $linkContent, ROK4_SYMLINK_SIGNATURE_SIZE;
            }
            elsif ($try == 1 && ($response->code == 401 || $response->code == 403)) {
                DEBUG("Authentication may have expired. Reconnecting...");
                if (! defined _getSwiftToken(TRUE)) {
                    ERROR("Reconnection attempt failed.");
                    return undef;
                }
                DEBUG("Successfully reconnected.");
                $try++;
            }
            else {
                ERROR("HTTP code: ", $response->code);
                ERROR("HTTP message: ", $response->message);
                ERROR("HTTP decoded content : ", $response->decoded_content);
                return undef;
            }
        }
    }

    return undef;
}

1;
__END__
