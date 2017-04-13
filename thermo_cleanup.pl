#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use File::Find;
use Time::Piece;

my $max_age = $ARGV[0] // 0; # in days

use constant IN  => "$ENV{HOME}/incoming";
use constant LOG => "$ENV{HOME}/cleanup.log";

find(
    {
        wanted => \&process,
        no_chdir => 1,
    }, 
    IN
);

sub process {

    my $fn = $_;
    next if (! -f $fn);
    next if (-M $fn <= $max_age);
    logger( "Cleaned up $fn" );
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

