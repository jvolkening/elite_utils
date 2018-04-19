package Elite::Handler::Converter;

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use File::Basename qw/basename fileparse/;
use File::Copy qw/copy/;
use File::HomeDir;
use File::Temp qw/tempfile/;
use File::Which qw/which/;
use Net::Rmsconvert;
use Paws;
use Try::Tiny;

use Data::Dumper;

use constant STATE_PENDING => 0;
use constant STATE_RUNNING => 16;

use constant POLL_INT    => 10;
use constant MAX_WAIT    => 300;
use constant MAX_TRY     => 3;
use constant SIZE_CUTOFF => 1024**3; # 1 GB


# these should be redefined by subclass
sub params {}
sub suffix {}


sub run {

    my ($class, %args) = @_;

    for (qw/config/) {
        die "Parameter $_ must be defined"
            if (! defined $args{$_});
    }

    my $self = bless {} => $class;
    for (keys %{$args{config}}) {
        $self->{$_} = $args{config}->{$_};
    }

    my $MSCONVERT = which('msconvert');

    # define output filename
    my $tgt_out = join '/',
        $self->{_output_path},
        basename($self->{_input_file}),
    ;
    my $suff = $self->suffix;
    $tgt_out =~ s/\.[^\.]+$/\.$suff/i;
    if (-e $tgt_out) {
        die "Target $tgt_out exists and won't overwrite\n";
    }

    # run locally if feasible
    if ($MSCONVERT && defined $self->{_mzml_file} && -e $self->{_mzml_file}) {
        $self->msconvert($MSCONVERT, $tgt_out);
    }
    else {
        $self->rmsconvert($tgt_out);
    }

    return $tgt_out;

}

sub msconvert {

    my ($self, $bin, $tgt_out) = @_;

    # run msconvert
    my ($out_fh, $out_fn) = tempfile(
        'msXXXXXXXXX',
        SUFFIX => '.tmp',
        TMPDIR => 1,
        UNLINK => 1,
    );
    my ($base,$path,$suff) = fileparse($out_fn, '.tmp');
    my $ret = system(
        $bin,
        @{ $self->params },
        '--outdir' => $path,
        '--outfile' => $base,
        '-e'        => '.tmp',
        $self->{_mzml_file},
    );
    die "msconvert failed: $!\n" if $ret;

    copy($out_fh, $tgt_out)
        or die "Error copying $out_fh to $tgt_out: $!\n";

    return 1;

}

sub rmsconvert {

    my ($self, $tgt_out) = @_;

    my $home = File::HomeDir->my_home;

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

    $self->{_rmsc} = $rmsc;

    $self->{_ua} = Paws->service('EC2', region => $self->{_aws_region});

    my $in_size = -s $self->{_input_file};

    my $inst_type = $in_size < SIZE_CUTOFF
        ? 't2.micro'
        : 't2.medium'
    ;

    $self->_run_instance($inst_type);

    my $tmp_out = File::Temp->new(UNLINK => 1);

    my $success = 0;
    my $i = MAX_TRY;
    while ($i > 0) {
        try {
            $self->_rmsconvert("$tmp_out");
            $i = 0;
        }
        catch {
            my $t = MAX_TRY - $i + 1;
            warn "Conversion try $i (of " . MAX_TRY . " max) failed\n";
            sleep 60;
            --$i;
        }
    }
    my $ret = $self->_terminate_instance;

    copy($tmp_out, $tgt_out)
        or die "Error copying mzML: $!\n";

    return 1;

}

sub _terminate_instance {

    my ($self) = @_;

    say "Terminating instance...";

    my $inst = $self->{_instance};

    my $states = $self->{_ua}->TerminateInstances(
        InstanceIds => [$inst->InstanceId]
    )->TerminatingInstances();

    my $n_states = scalar @{$states};
    die "Expected one state and got $n_states"
        if ($n_states != 1);

    if ($states->[0]->CurrentState()->Code > STATE_RUNNING) {
        say "instance terminated succcessfully";
        $self->{_instance} = undef;
        return 1;
    }
    say "instance failed to terminate";
    return 0;

}

sub _run_instance {

    say "Booting instance...";

    my ($self, $type) = @_;

    my $reserv = $self->{_ua}->RunInstances(
        ImageId          =>  $self->{_rmsc}->{image_id},
        InstanceType     =>  $type,
        SecurityGroupIds => [$self->{_rmsc}->{security_group}],
        MinCount         =>  1,
        MaxCount         =>  1,
    );

    my $instance = _validate_instance($reserv);

    # loop until instance is no longer pending or we time out
    my $elapsed = 0;
    while ($instance->State()->Code == STATE_PENDING && $elapsed <= MAX_WAIT) {
        say "  waiting...";
        sleep POLL_INT;
        $elapsed += POLL_INT;
        $reserv = $self->{_ua}->DescribeInstances(
            InstanceIds => [$instance->InstanceId]
        )->Reservations()->[0];
        $instance = _validate_instance($reserv);
    }

    if ($instance->State()->Code != STATE_RUNNING) {
        warn "Instance failed to run in time allotted\n";
        warn "Final state was " . $instance->State()->name . "\n";
        exit 1;
    }

    $self->{_instance} = $instance;
    $self->{_server}   = $self->{_instance}->PublicDnsName
        // die "unknown DNS name";

}

sub _validate_instance {

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

sub _rmsconvert {

    say "Running rmsconvert";

    my ($self, $fn_out) = @_;

    my $ca = Net::Rmsconvert->new(
        server      => $self->{_server},
        port        => 22223,
        timeout     => 50000,
        compression => 'gzip',
        params      => $self->params,
        ssl_key => $self->{_rmsc}->{ssl_key},
        ssl_crt => $self->{_rmsc}->{ssl_crt},
        ssl_ca  => $self->{_rmsc}->{ssl_ca},
    );
    $ca->convert($self->{_input_file} => $fn_out)
        or die "Error converting file\n";

}

sub DESTROY {

    my ($self) = @_;
    return if (! defined $self->{_instance});
    $self->_terminate_instance;

}

1;
