#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::HomeDir;
use Net::Amazon::Glacier;
use Net::Rmsconvert;
use Digest::SHA qw/sha256/;

++$|;

my ($fn_out, $v_name, $ar_id, $job_id) = @ARGV;

my $home = File::HomeDir->my_home;

# read in credentials and configuration values from standard locations
my $cred = Config::Tiny->read("$home/.aws/credentials")
    or die "Error reading credentials file:", Config::Tiny->errstr;
die "No appropriate key id found\n"
    if (! defined $cred->{rmsconvert}->{aws_access_key_id});
die "No appropriate secret key found\n"
    if (! defined $cred->{rmsconvert}->{aws_secret_access_key});
my $conf = Config::Tiny->read("$home/.aws/config")
    or die "Error reading config file:", Config::Tiny->errstr;
die "No appropriate region found\n"
    if (! defined $conf->{rmsconvert}->{region});

my $ua = Net::Amazon::Glacier->new(
    $conf->{rmsconvert}->{region},
    $cred->{rmsconvert}->{aws_access_key_id},
    $cred->{rmsconvert}->{aws_secret_access_key}
);

if (! defined $job_id) { 

    $job_id = $ua->initiate_archive_retrieval(
        $v_name,
        $ar_id,
    );

}

while (1) {

    my $resp = $ua->describe_job(
        $v_name,
        $job_id,
    );
    last if ($resp->{Completed});

    print '.';
    sleep 60;

}

my $blob = $ua->get_job_output(
    $v_name,
    $job_id,
);

open my $fh_out, '>:raw', $fn_out;
print {$fh_out} $blob;
close $fh_out;

say "success";

