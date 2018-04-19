#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Getopt::Long;
use Elite;

my $DIR_IN  = "$ENV{HOME}/incoming";
my $DIR_OUT = "$ENV{HOME}/shared";
my $LOG_FILE = "$ENV{HOME}/transfer.log";
my $ADMIN_EMAIL;

GetOptions(
    'admin_email=s' => \$ADMIN_EMAIL,
    'dir_in=s'      => \$DIR_IN,
    'dir_out=s'     => \$DIR_OUT,
    'log_file=s'     => \$LOG_FILE,
) or die "Error parsing options: $@\n";

die "Admin email not valid!"
    if ( ! Email::Valid->address($ADMIN_EMAIL) );

my $handler = Elite->new(
    dir_in      => $DIR_IN,
    dir_out     => $DIR_OUT,
    admin_email => $ADMIN_EMAIL,
    log_file    => $LOG_FILE,
);

$handler->run();

exit;

