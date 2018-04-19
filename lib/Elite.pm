package Elite;

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use Digest::MD5;
use Email::Valid;
use File::Copy qw/copy/;
use File::Path qw/make_path/;
use Linux::Inotify2;
use Net::Domain qw/hostfqdn/;
use Net::SMTP;
use Time::Piece;

use constant ERROR => 0;
use constant WARN  => 1;
use constant INFO  => 2;

my %class_msg = (
    ERROR => 'ERROR',
    WARN  => 'WARNING',
    INFO  => 'INFO',
);

#----------------------------------------------------------------------------#

sub new {

    my ($class, %args) = @_;

    if ( defined $args{admin_email}
            && ! Email::Valid->address($args{admin_email}) ) {
        die "Admin email not valid!"
    }

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
    return if (! $cfg->{transfer});

    # validate provided metadata

    for (qw/email galaxy_user/) {
    if (defined $cfg->{$_} && ! Email::Valid->address($cfg->{$_})) {
        $self->_log( WARN, "User provided invalid $_ address ($cfg->{$_})" );
    }

    if (! length $cfg->{path}) {
        $self->_log( ERROR, "No path defined in $fn" );
        return;
    }
    if ($cfg->{path} =~ /\.\./);
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
        
    $cfg->{_input_file} = "$self->{dir_in}/$self->{path}$self->{file}";
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
    
    my $out_path = "$self->{dir_out}/$self->{path}";
    if (! -e $out_path) {
        if (! make_path($out_path) ) {
            $self->_log( ERROR, "Problem creating output path $out_path: $!" );
            return;
        }
    }
    elsif (! -d $out_path) {
        $self->_log( ERROR, "Output path $out_path exists but is not a directory" );
        return;
    }

    $self->{_output_file} = "$out_path$self->{file}";

    if (-e $self->{_output_file}) {
        $self->_log(ERROR, "File $self->{_output_file} exists and will not be overwritten" );
        return;
    }

    if (! copy( $self->{_input_file} => $self->{_output_file} ) ) {
        $self->_log( ERROR, "Failure copying $self->{file}: $!" );
        return;
    }
        
    $self->_log( INFO, "Successfully transferred $path$file" );
    
}

sub _log {

    my ($self, $class, $msg) = @_;

    $msg =  join "\t",
        localtime()->datetime(),
        $class_msg{$class},
        $msg;

    # print to log

    open my $log, '>>', $self->{log_file};
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

