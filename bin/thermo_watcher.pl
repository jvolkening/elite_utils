#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Getopt::Long;
use Thermo;

my $DIR_IN       = "$ENV{HOME}/incoming";
my $DIR_OUT      = "$ENV{HOME}/shared";
my $LOG_FILE     = "$ENV{HOME}/transfer.log";
my $AWS_REGION   = 'us-east-2';
my $SNS_REGION   = 'us-east-1';
my $COUNTRY_CODE = '+1'; # default US
my $MACHINE_NAME = 'Orbitrap Elite';
my $GALAXY_URL   = 'http://localhost:8080';
my $ADMIN_EMAIL;
my $VAULT_NAME;

GetOptions(
    'admin_email=s'  => \$ADMIN_EMAIL,
    'dir_in=s'       => \$DIR_IN,
    'dir_out=s'      => \$DIR_OUT,
    'log_file=s'     => \$LOG_FILE,
    'machine_name=s' => \$MACHINE_NAME,
    'country_code=s' => \$COUNTRY_CODE,
    'aws_region=s'   => \$AWS_REGION,
    'sns_region=s'   => \$SNS_REGION,
    'vault_name=s'   => \$VAULT_NAME,
    'galaxy_url=s'   => \$GALAXY_URL,
) or die "Error parsing options: $@\n";

my $handler = Thermo->new(
    dir_in       => $DIR_IN,
    dir_out      => $DIR_OUT,
    admin_email  => $ADMIN_EMAIL,
    log_file     => $LOG_FILE,
    machine_name => $MACHINE_NAME,
    country_code => $COUNTRY_CODE,
    aws_region   => $AWS_REGION,
    sns_region   => $SNS_REGION,
    vault_name   => $VAULT_NAME,
    galaxy_url   => $GALAXY_URL,
);

$handler->run();

exit;

