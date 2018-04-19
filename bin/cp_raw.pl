#!/usr/bin/env perl

use strict;
use warnings;

use 5.012;

use Cwd qw/abs_path/;
use Digest::MD5;
use Encode qw/decode/;
use File::Basename qw/basename fileparse/;
use File::Copy;
use File::Path qw/make_path/;
use File::Temp;
use Getopt::Long;
use Time::Piece;

my $EXTRA        = 'Orbi_data';

my $dest_dir = "T:/incoming";
my $fn_raw;
my $formats;
my $notify;
my $galaxy;
my $workflow;

GetOptions(
    'in=s'          => \$fn_raw,
    'formats'       => \$formats,
    'notify=s'      => \$notify,
    'galaxy_user=s' => \$galaxy,
    'workflow=s'    => \$workflow,
    'destination=s' => \$dest_dir,
) or die "ERROR parsing command line: $@\n";

die "ERROR: No such RAW file or file not readable\n"
    if (! -r $fn_raw);

my (
    $filename,
    $head_formats,
    $head_notify,
    $head_galaxy,
    $head_workflow,
    $other
) = parse_raw($fn_raw);

$formats  //= $head_formats;
$notify   //= $head_notify;
$galaxy   //= $head_galaxy;
$workflow //= $head_workflow;

my ($base, $path, $suff) = fileparse( abs_path($fn_raw) );

$path =~ s/^[A-Z]\:[\\\/]//i
   or die "ERROR: RAW file path must be absolute\n";
$path =~ s/$EXTRA[\\\/]//i;

my $out_path = "$dest_dir/$path";
my $fn_dest  = "$out_path$base";

if (! -e $out_path) {
    if (! make_path($out_path) ) {
        logger( "ERROR creating path $out_path" );
        return;
    }
}

die "Formats cannot contain carriage return"
    if ($formats =~ /\n/);

die "ERROR: $fn_dest exists and won't overwrite\n"
    if (-e $fn_dest);

copy( $fn_raw => $fn_dest )
    or die "ERROR transfering file: $!\n";

my $size = -s $fn_raw;

# calculate checksum
open my $in, '<:raw', $fn_raw
    or die "Failed to open $fn_raw for reading\n";
my $dig = Digest::MD5->new;
$dig->addfile($in);


# prepare 'ready' file
my $ready  = File::Temp->new(
    DIR    => $dest_dir,
    UNLINK => 0,
    SUFFIX => '.ready',
);
say {$ready} "path=",        $path;
say {$ready} "time=",        localtime()->datetime;
say {$ready} "formats=",     $formats;
say {$ready} "md5=",         $dig->hexdigest;
say {$ready} "size=",        $size;
say {$ready} "file=",        $base;
say {$ready} "galaxy_user=", $galaxy;
say {$ready} "notify=",      $notify;
say {$ready} "workflow=",    $workflow;
say {$ready} "done=",        '1';

close $ready;

exit;



sub parse_raw {

    my ($fn) = @_;

    open my $raw, '<:raw', $fn;

    my $magic = read_bin($raw => 'v');
    die "Bad magic\n" if ($magic != 0xa101);
    my $sig = decode('UTF-16LE', read_bin($raw => 'a18') );
    die "Bad sig\n" if ($sig ne "Finnigan\0");

    # skip rest of header
    seek $raw, 1336, 1;
    # skip injection data
    seek $raw, 64, 1;

    my @fields = map {read_pascal($raw)} 1..13;

    my $user_1    = $fields[ 4];
    my $user_2    = $fields[ 5];
    my $user_3    = $fields[ 6];
    my $user_4    = $fields[ 7];
    my $user_5    = $fields[ 8];
    my $filename  = $fields[11];
    my $filepath  = $fields[12];

    $filename = "$filepath/" . basename($filename);
    die "Parsed filename not found\n"
        if (! -e $filename);

    return ($filename, $user_1, $user_2, $user_3, $user_4, $user_5);

}

sub read_bin {

    my ($fh, $type) = @_;
    my $len = length(pack($type,()));
    my $r = read($fh, my $buf, $len);
    die "Wrong number of bytes read (want $len, got $r)\n"
        if ($r != $len);

   return unpack "$type*", $buf;

}

sub read_pascal {

    my ($fh) = @_;
    my $buf;
    my $r = read $fh, $buf, 4;
    my $n_char = unpack 'V', $buf;

    $r = read $fh, $buf, $n_char * 2;
    return decode('UTF-16LE', $buf);

}
