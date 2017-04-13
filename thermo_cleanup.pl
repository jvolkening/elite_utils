#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Time::Piece;

my $max_age = $ARGV[0] // 0; # in days

use constant IN  => "$ENV{HOME}/incoming";
use constant LOG => "$ENV{HOME}/cleanup.log";

for my $candidate (glob IN . '/*') {

    next if (-M $candidate <= $max_age);
    logger( "Cleaned up $candidate" );
    #unlink $candidate;

}

sub logger {

    my ($msg) = @_;

    open my $log, '>>', LOG
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} join "\t",
        localtime()->datetime(),
        $msg;

}

