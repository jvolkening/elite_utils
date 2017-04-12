#!/usr/bin/env perl

use strict;
use warnings;

use 5.012;

use Digest::MD5;
use File::Basename qw/basename/;
use File::Path qw/make_path/;
use File::Copy;
use File::Which;
use Getopt::Long;
use Time::Piece;

my $DEST_DIR = "T:/incoming";

my $fn_raw;
my $user = 'other';
my $mzml = 0;

GetOptions(
    'raw=s'  => \$fn_raw,
    'user=s' => \$user,
    'mzml'   => \$mzml,
) or die "ERROR parsing command line: $@\n";

die "ERROR: No such RAW file or file not readable\n"
    if (! -r $fn_raw);

die "Invalid user name (max 16 chars w/ only alphanumerics and underscore)\n"
    if ($user =~ /\W/ || length($user) > 16);

my $base     = basename($fn_raw);
my $fn_dest  = "$DEST_DIR/$base";
my $fn_ready = "$DEST_DIR/$base.ready";

# make sure value of $mzml is numeric
$mzml = $mzml ? 1 : 0;

die "ERROR: $fn_ready exists and won't overwrite\n"
    if (-e $fn_ready);

die "ERROR: $fn_dest exists and won't overwrite\n"
    if (-e $fn_dest);

copy( $fn_raw => $fn_dest )
    or die "ERROR transfering file: $!\n";

my $size = -s $fn_raw;

# calculate checksum
open my $in, '<', $fn_raw
    or die "Failed to open $fn_raw for reading\n";
my $dig = Digest::MD5->new;
$dig->addfile($in);


# prepare 'ready' file
open my $ready, '>', $fn_ready
    or die "ERROR creating ready file: $!\n";
say {$ready} "user=", $user;
say {$ready} "time=", localtime()->datetime;
say {$ready} "mzml=", $mzml;
say {$ready} "type=", 'raw';
say {$ready} "md5=",  $dig->hexdigest;
say {$ready} "size=", $size;
say {$ready} "file=", $base;
say {$ready} "done=", '1';

close $ready;

exit;

