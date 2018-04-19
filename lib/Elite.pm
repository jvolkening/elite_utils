package Elite;

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use Digest::MD5;
use Email::Valid;
use File::Path qw/make_path/;
use Linux::Inotify2;
use List::Util qw/any/;
use Net::Domain qw/hostfqdn/;
use Net::SMTP;
use Time::Piece;
use Try::Tiny;

use Elite::Handler::Raw;
use Elite::Handler::MzML;
use Elite::Handler::MGF;
use Elite::Handler::Notify;
use Elite::Handler::GalaxyUpload;
use Elite::Handler::GalaxyRun;

use constant ERROR => 0;
use constant WARN  => 1;
use constant INFO  => 2;

my %class_msg = (
    ERROR , 'ERROR',
    WARN  , 'WARNING',
    INFO  , 'INFO',
);

#----------------------------------------------------------------------------#

sub new {

    my ($class, %args) = @_;

    if ( defined $args{admin_email}
            && ! Email::Valid->address($args{admin_email}) ) {
        die "Admin email not valid!"
    }

    # set defaults
    $args{default_country} //= '+1'; # default to US
    $args{aws_region}      //= 'us-east-2';
    $args{sns_region}      //= 'us-east-1';
    $args{machine_name}    //= 'Orbitrap Elite';

    die "Incoming directory not found"
        if (! -e $args{dir_in});
    die "Outgoing directory not found"
        if (! -e $args{dir_out});
    die "Must specify logfile"
        if (! defined $args{log_file});

    return bless {%args} => $class;

}

#----------------------------------------------------------------------------#

sub run {
    
    my ($self) = @_;

    my $inotify = Linux::Inotify2->new()
        or die "Unable to create Inotify2 obj: $!\n";

    $inotify->watch(
        $self->{dir_in},
        IN_MOVED_TO|IN_CLOSE_WRITE,
        sub {$self->_handle_new(@_)},
    );

    1 while $inotify->poll;

}

#----------------------------------------------------------------------------#

sub _handle_new {

    my ($self, $ev) = @_;
    my $fn = $ev->fullname;

    return if ($fn !~ /\.ready$/i);

    my $cfg;

    # wait for READY file to finish writing
    for (1..10) {
        if ($cfg = Config::Tiny->read($fn)) {
            $cfg = $cfg->{_};
            last if ($cfg->{done});
            sleep 2;
        }
        else {
            $self->_log( ERROR, "Failed to parse ready file $fn" );
            return;
        }
    }
    return if (! $cfg->{done});

    # copy defaults
    $cfg->{_default_country} = $self->{default_country};
    $cfg->{_aws_region}      = $self->{aws_region};
    $cfg->{_sns_region}      = $self->{sns_region};
    $cfg->{_machine_name}    = $self->{machine_name};

    # validate provided metadata

    my @fmts = split /,\s*/, $cfg->{formats};

    for (qw/email galaxy_user/) {
        if (length $cfg->{$_} && ! Email::Valid->address($cfg->{$_})) {
            $self->_log( WARN, "User provided invalid $_ address ($cfg->{$_})" );
        }
    }

    if (! length $cfg->{path}) {
        $self->_log( ERROR, "No path defined in $fn" );
        return;
    }
    if ($cfg->{path} =~ /\.\./) {
        $self->_log( ERROR, "No backtracking allowed in path for $fn" );
        return;
    }

    if (! length $cfg->{file}) {
        $self->_log( ERROR, "No file defined in $fn" );
        return;
    }
    if ($cfg->{file} =~ /[\\\/\&\|\;]/) {
        $self->_log( ERROR, "Invalid filename $cfg->{file}" );
        return;
    }
        
    $cfg->{_input_file} = "$self->{dir_in}/$cfg->{path}$cfg->{file}";
    if (open my $input, '<:raw', $cfg->{_input_file}) {

        my $digest = Digest::MD5->new();
        $digest->addfile($input);
        if ($digest->hexdigest() ne $cfg->{md5}) {
            $self->_log( ERROR, "Bad digest for $cfg->{file}" );
            return;
        }

    }
    else {
        $self->_log( ERROR, "Failed to open file $cfg->{_actual_path}: $!" );
        return;
    }
   
    if (length $cfg->{formats}) {
        $cfg->{_output_path} = "$self->{dir_out}/$cfg->{path}";
        if (! -e $cfg->{_output_path}) {
            if (! make_path($cfg->{_output_path}) ) {
                $self->_log( ERROR, "Problem creating output path $cfg->{_output_path}: $!" );
                return;
            }
        }
        elsif (! -d $cfg->{_output_path}) {
            $self->_log( ERROR, "Output path $cfg->{_output_path} exists but is not a directory" );
            return;
        }
    }

    #------------------------------------------------------------------------#
    # transfer RAW files
    #------------------------------------------------------------------------#

    if (any {$_ =~ /^raw$/i} @fmts) {
        try {
            Elite::Handler::Raw->run(
                config  => $cfg,
                archive => 0,
            );
            $self->_log( INFO, "Successfully transferred $cfg->{path}$cfg->{file}" );
        }
        catch {
            $self->_log( ERROR, "Failure transferring $cfg->{path}$cfg->{file}: $_" );
        }
    }

    #------------------------------------------------------------------------#
    # convert to MzML
    #------------------------------------------------------------------------#

    if (any {$_ =~ /^mzml$/i} @fmts) {
        try {
            my $fn = Elite::Handler::MzML->run(
                config  => $cfg,
            );
            $self->_log( INFO, "Successfully converted $cfg->{path}$cfg->{file} to MzML" );
            $cfg->{_mzml_file} = $fn;
        }
        catch {
            $self->_log( INFO, "Failure converting $cfg->{path}$cfg->{file} to MzML: $_" );
        }
    }

    #------------------------------------------------------------------------#
    # convert to MGF
    #------------------------------------------------------------------------#

    if (any {$_ =~ /^mgf$/i} @fmts) {
        try {
            Elite::Handler::MGF->run(
                config  => $cfg,
            );
            $self->_log( INFO, "Successfully converted $cfg->{path}$cfg->{file} to MGF" );
        }
        catch {
            $self->_log( INFO, "Failure converting $cfg->{path}$cfg->{file} to MGF: $_" );
        }
    }

    #------------------------------------------------------------------------#
    # upload to galaxy
    #------------------------------------------------------------------------#

    if ($cfg->{galaxy_user}) {
        try {
            Elite::Handler::GalaxyUpload->run(
                config  => $cfg,
            );
            $self->_log( INFO, "Successfully uploaded $cfg->{path}$cfg->{file} to Galaxy" );
        }
        catch {
            $self->_log( INFO, "Failure uploading $cfg->{path}$cfg->{file} to Galaxy: $_" );
        }
    }

    #------------------------------------------------------------------------#
    # send notifications (do this after conversions and uploads)
    #------------------------------------------------------------------------#

    if ($cfg->{notify}) {
        try {
            my ($passed, $failed) = Elite::Handler::Notify->run(
                config  => $cfg,
            );
            if (scalar @$passed) {
                $self->_log( INFO, "Successfully sent notifications for $cfg->{path}$cfg->{file} to @$passed" );
            }
            if (scalar @$failed) {
                $self->_log( INFO, "Failed sending notifications for $cfg->{path}$cfg->{file} to @$failed" );
            }
        }
        catch {
            $self->_log( ERROR, "Failure sending notifications for $cfg->{path}$cfg->{file}: $_" );
        }
    }


    #------------------------------------------------------------------------#
    # trigger workflow
    #------------------------------------------------------------------------#

    if ($cfg->{workflow}) {
        try {
            Elite::Handler::GalaxyRun->run(
                config  => $cfg,
            );
            $self->_log( INFO, "Successfully ran workflow $cfg->{workflow} on $cfg->{file}" );
        }
        catch {
            $self->_log( INFO, "Failure running workflow $cfg->{workflow} on $cfg->{file}: $_" );
        }
    }
    
}

sub _log {

    my ($self, $class, $msg) = @_;

    $msg =~ s/[\n\r]//g;
    $msg =  join "\t",
        localtime()->datetime(),
        $class_msg{$class},
        $msg;

    # print to log

    open my $log, '>>', $self->{log_file}
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} $msg;
    close $log;


    # send email if any valid addresses given

    my $email = $self->{admin_email};
    return if (! defined $email);
    
    my $sender = "thermo_watcher@" . hostfqdn();

    my $smtp = Net::SMTP->new('localhost','Debug'=>0)
        or return;
    $smtp->mail($sender);
    $smtp->to($email);

    $smtp->data();
    $smtp->datasend("To: $email\n");
    $smtp->datasend("From: $sender\n");
    $smtp->datasend("Subject: thermo_watcher notification\n");
    $smtp->datasend("\n");
    $smtp->datasend($msg);
    $smtp->dataend();

    $smtp->quit();

}

1;
