#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::HomeDir;
use Paws;
use Net::Rmsconvert;
use Try::Tiny;

use constant STATE_PENDING => 0;
use constant STATE_RUNNING => 16;

# always run END block
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = $SIG{HUP} = sub { die; };

my ($fn_in, $fn_out) = @ARGV;

my $poll_int = 10;
my $max_wait = 300; # 5 minutes
my $max_try  = 5;

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
my $rmsc = Config::Tiny->read("$home/.rmsconvert")
    or die "Error reading rmsconvert config file:", Config::Tiny->errstr;
$rmsc = $rmsc->{_};
die "No appropriate security group found\n"
    if (! defined $rmsc->{security_group});
die "No appropriate instance type found\n"
    if (! defined $rmsc->{instance_type});
die "No appropriate image ID found\n"
    if (! defined $rmsc->{image_id});
die "No appropriate SSL key found\n"
    if (! defined $rmsc->{ssl_key});
die "No appropriate SSL cert found\n"
    if (! defined $rmsc->{ssl_crt});
die "No appropriate SSL CA found\n"
    if (! defined $rmsc->{ssl_ca});

my $ua = Paws->service('EC2', region => $conf->{rmsconvert}->{region});

my $instance;
run_instance();
my $server = $instance->dns_name // die "unknown DNS name";
for my $i (1..$max_try) {
    try {
        convert($fn_in, $fn_out, $server);
        last;
    }
    catch {
        warn "Conversion try $i (of $max_try max) failed\n";
        sleep 60;
    }
}
my $ret = terminate_instance($instance);


sub terminate_instance {

    my ($inst) = @_;

    say "Terminating instance...";

    my $states = $ua->TerminateInstances(
        InstanceIds => [$inst->InstanceId]
    )->TerminatingInstances();

    my $n_states = scalar @{$states};
    die "Expected one state and got $n_states"
        if ($n_states != 1);

    if ($states->[0]->CurrentState()->Code > STATE_RUNNING) {
        say "instance terminated succcessfully";
        $instance = undef;
        return 1;
    }
    say "instance failed to terminate";
    return 0;

}

sub run_instance {

    say "Booting instance...";

    my $reserv = $ua->RunInstances(
        ImageId => $rmsc->{image_id},
        MinCount => 1,
        MaxCount => 1,
        SecurityGroupIds => [$rmsc->{security_group}],
        InstanceType => $rmsc->{instance_type},
    );

    $instance = validate_instance($reserv);

    # loop until instance is no longer pending or we time out
    my $elapsed = 0;
    while ($instance->State()->Code == STATE_PENDING && $elapsed <= $max_wait) {
        say "  waiting...";
        sleep $poll_int;
        $elapsed += $poll_int;
        $reserv = $ua->DescribeInstances(
            InstanceIds => [$instance->InstanceId]
        )->Reservations()->[0];
        $instance = validate_instance($reserv);
    }

    if ($instance->State()->Code != STATE_RUNNING) {
        warn "Instance failed to run in time allotted\n";
        warn "Final state was " . $instance->State()->name . "\n";
        exit 1;
    }

}

sub validate_instance {

    # currently, just checks that a single instance is present and returns
    # that instance

    my ($reserv) = @_;

    # flatten array ref if given
    if (ref($reserv) eq 'ARRAY') {
        my $n_reserv = scalar @{$reserv};
        die "Expected 1 reservation object and got $n_reserv"
            if ($n_reserv != 1);
        $reserv = $reserv->[0];
    }

    my @instances = @{ $reserv->Instances };
    my $n_inst = scalar @instances;
    die "Expected exactly one running instance, got $n_inst"
        if ($n_inst != 1);

    return $instances[0];

}

sub convert {

    say "Running rmsconvert";

    my ($fn_in, $fn_out, $server) = @_;

    my $ca = Net::Rmsconvert->new(
        server      => $server,
        port        => 22223,
        timeout     => 50000,
        compression => 'gzip',
        params      => [
            '--mzML',
            '--gzip',
            '--numpressAll',
            '--filter' => 'peakPicking true 1-',
        ],
        ssl_key => $rmsc->{ssl_key},
        ssl_crt => $rmsc->{ssl_crt},
        ssl_ca  => $rmsc->{ssl_ca},
    );
    $ca->convert($fn_in => $fn_out)
        or die "Error converting file\n";

}

# always try terminate an instance if still running
END {

    return if (! defined $instance);
    terminate_instance($instance);

}
