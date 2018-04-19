#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::HomeDir;
use Net::Amazon::Glacier;
use Net::Rmsconvert;
use Digest::SHA qw/sha256/;

require bytes;

use constant MB => 1024**2;

my ($fn_in, $v_name) = @ARGV;

my $poll_int = 10;
my $max_wait = 300; # 5 minutes

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
    

my $part_size  =  4 * MB;
my $block_size =  1 * MB;

my $file_size = -s $fn_in;

open my $fh_in, '<:raw', $fn_in;



my $up_id = $ua->multipart_upload_init(
    $v_name,
    $part_size,
    'foo archive',
);

my @part_hashes = ();

my $buffer;
my $total_read = 0;
my $n = 0;
while (my $r = read $fh_in, $buffer, $part_size) {

    say "Uploading chunk $n...";
   
    my $range_start = $total_read;
    $total_read += $r;
    if ($r != $part_size && $total_read != $file_size) {
        die "Read unexpected number of bytes ($r)";
    }

    my $tree = $ua->multipart_upload_upload_part(
        $v_name,
        $up_id,
        $part_size,
        $n,
        \$buffer,
    );

    push @part_hashes, $tree;
    ++$n;
}

my $ar_id = $ua->multipart_upload_complete(
    $v_name,
    $up_id,
    \@part_hashes,
    $file_size,
);
say $ar_id;
$up_id = undef;
say "success";

END {

    return if (! defined $up_id);

    $ua->multipart_upload_abort(
        $v_name,
        $up_id,
    );
    say "Aborted upload";

}
