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

my $DEST_DIR = "T:/incoming";
my $DEFAULT_USER = 'other';
my $EXTRA = 'Orbi_data';

my $fn_raw;
my $mzml;
my $mgf;

GetOptions(
    'raw=s'  => \$fn_raw,
    'mzml'   => \$mzml,
    'mgf'    => \$mgf,
) or die "ERROR parsing command line: $@\n";

die "ERROR: No such RAW file or file not readable\n"
    if (! -r $fn_raw);

my ($filename, $head_mzml, $head_mgf) = parse_raw($fn_raw);

$mzml = defined $mzml      ? $mzml
      : defined $head_mzml ? $head_mzml
      : 0;

$mgf  = defined $mgf      ? $mgf
      : defined $head_mgf ? $head_mgf
      : 0;

my ($base, $path, $suff) = fileparse( abs_path($fn_raw) );

$path =~ s/^[A-Z]\:[\\\/]//
   or die "ERROR: RAW file path must be absolute\n";
$path =~ s/$EXTRA[\\\/]//;

my $out_path = "$DEST_DIR/$path";
my $fn_dest  = "$out_path$base";

if (! -e $out_path) {
    if (! make_path($out_path) ) {
        logger( "ERROR creating path $out_path" );
        return;
    }
}

# make sure values of $mzml and $mgf are numeric
$mzml = $mzml ? 1 : 0;
$mgf  = $mgf  ? 1 : 0;

die "ERROR: $fn_dest exists and won't overwrite\n"
    if (-e $fn_dest);

warn "cp $fn_raw => $fn_dest\n";
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
    DIR    => $DEST_DIR,
    UNLINK => 0,
    SUFFIX => '.ready',
);
say {$ready} "path=", $path;
say {$ready} "time=", localtime()->datetime;
say {$ready} "mzml=", $mzml;
say {$ready} "mgf=",  $mgf;
say {$ready} "type=", 'raw';
say {$ready} "md5=",  $dig->hexdigest;
say {$ready} "size=", $size;
say {$ready} "file=", $base;
say {$ready} "done=", '1';

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
    my $filename  = $fields[11];
    my $filepath  = $fields[12];

    $filename = "$filepath/" . basename($filename);
    die "Parsed filename not found\n"
        if (! -e $filename);

    return ($filename, $user_1, $user_2);

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
