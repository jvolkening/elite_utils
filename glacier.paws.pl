#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::HomeDir;
use Paws;
use Net::Rmsconvert;
use Digest::SHA qw/sha256/;

require bytes;

use constant MB => 1024**2;

my ($fn_in, $v_name) = @ARGV;

my $poll_int = 10;
my $max_wait = 300; # 5 minutes

my $home = File::HomeDir->my_home;

my $ua = Paws->service('Glacier', region => 'us-east-2', debug => 1);

my $part_size  =  4 * MB;
my $block_size =  1 * MB;

my $file_size = -s $fn_in;

open my $fh_in, '<:raw', $fn_in;

my $res = $ua->InitiateMultipartUpload(
    AccountId          => '-',
    VaultName          => $v_name,
    ArchiveDescription => 'foo archive',
    PartSize           => $part_size,
);
my $up_id = $res->UploadId;

my @part_hashes = ();

my $buffer;
my $total_read = 0;
my $n = 0;
while (my $r = read $fh_in, $buffer, $part_size) {

    say "Uploading chunk $n...";
    ++$n;
   
    my $range_start = $total_read;
    $total_read += $r;
    if ($r != $part_size && $total_read != $file_size) {
        die "Read unexpected number of bytes ($r)";
    }

    my $actual_len = bytes::length($buffer);

    my $template = "a$block_size" x int($actual_len/$block_size);
    $template .= 'a*' if ($actual_len % $block_size);

    my @hashes = map {sha256($_)} unpack $template, $buffer;

    my $tree = tree_hash(@hashes);

    my $range = 'bytes '
        . $range_start
        . '-'
        . $total_read - 1;

    my $resp = $ua->UploadMultipartPart(
        AccountId => '-',
        UploadId  => $up_id,
        VaultName => $v_name,
        Body      => $buffer,
        Checksum  => $tree,
        Range     => $range,
    );

    push @part_hashes, $tree;

}

my $final_tree = tree_hash(@part_hashes);

my $resp = $ua->CompleteMultipartUpload(
    AccountId => '-',
    UploadId    => $up_id,
    VaultName   => $v_name,
    ArchiveSize => $file_size,
    Checksum    => $final_tree,
);

say $resp->ArchiveId;
$up_id = undef;


sub tree_hash {

    my (@tree) = @_;

    while (@tree > 1) {
        my @tmp = @tree;
        @tree = ();
        while (@tmp > 1) {
            push @tree, sha256(shift(@tmp) . shift(@tmp));
        }
        push @tree, @tmp;
    }

    return $tree[0];

}
            


END {

    return if (! defined $up_id);

    my $resp = $ua->AbortMultiPartUpload(
        AccountId => '-',
        UploadId  => $up_id,
    );
    say "Aborted upload";

}
