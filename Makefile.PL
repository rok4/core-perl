#!/usr/bin/perl -w

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME        => "ROK4::Core",
    BUILD_REQUIRES => { 
        "ExtUtils::MakeMaker" => 0
    },
    PREREQ_FATAL => 1,
    # ack -h "^use [A-Z]" ./ | cut -d' ' -f2 | grep -v -E "ROK4::" | sed -r "s#;##" | sort | uniq | sed -r "s/(.+)/\"\1\" => 0,/"
    PREREQ_PM => {
        "Amazon::S3" => 0,
        "Config::INI::Reader" => 0,
        "Cwd" => 0,
        "Data::Dumper" => 0,
        "DBI" => 0,
        "Devel::Size" => 0,
        "Digest::SHA" => 0,
        "Encode" => 0,
        "ExtUtils::MakeMaker" => 0,
        "File::Basename" => 0,
        "File::Copy" => 0,
        "File::Map" => 0,
        "File::Path" => 0,
        "File::Spec" => 0,
        "File::Spec::Link" => 0,
        "Geo::GDAL" => 0,
        "Geo::OGR" => 0,
        "Geo::OSR" => 0,
        "HTTP::Request" => 0,
        "HTTP::Request::Common" => 0,
        "HTTP::Response" => 0,
        "JSON" => 0,
        "JSON::Parse" => 0,
        "List::Util" => 0,
        "Log::Log4perl" => 0,
        "LWP::UserAgent" => 0,
        "Math::BigFloat" => 0,
        "Scalar::Util" => 0,
        "Test::More" => 0,
        "Tie::File" => 0,
        "XML::LibXML" => 0
    }
);
