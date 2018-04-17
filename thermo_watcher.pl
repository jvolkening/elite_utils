#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use Digest::MD5;
use Email::Valid;
use File::Copy qw/copy/;
use File::Path qw/make_path/;
use Getopt::Long;
use Linux::Inotify2;
use Net::Domain qw/hostfqdn/;
use Net::SMTP;
use Time::Piece;

my $DIR_IN  = "$ENV{HOME}/incoming";
my $DIR_OUT = "$ENV{HOME}/shared";
my $LOGFILE = "$ENV{HOME}/transfer.log";
my $ADMIN_EMAIL;

GetOptions(
    'admin_email=s' => \$ADMIN_EMAIL,
    'dir_in=s'      => \$DIR_IN,
    'dir_out=s'     => \$DIR_OUT,
    'logfile=s'     => \$LOGFILE,
) or die "Error parsing options: $@\n";

die "Admin email not valid!"
    if ( ! Email::Valid->address($ADMIN_EMAIL) );

#----------------------------------------------------------------------------#
#----------------------------------------------------------------------------#

my $inotify = Linux::Inotify2->new()
    or die "Unable to create Inotify2 obj: $!\n";

$inotify->watch(
    $DIR_IN,
    IN_MOVED_TO|IN_CLOSE_WRITE,
    \&handle_new,
);

1 while $inotify->poll;

#----------------------------------------------------------------------------#
#----------------------------------------------------------------------------#

sub handle_new {

    my ($ev) = @_;
    my $fn = $ev->fullname;

    return if ($fn !~ /\.ready$/i);

    my $cfg;
    for (1..10) {
        if ($cfg = Config::Tiny->read($fn)) {
            $cfg = $cfg->{_};
            last if ($cfg->{done});
            sleep 2;
        }
        else {
            logger(
                "ERROR: failed to parse ready file $fn",
                $ADMIN_EMAIL,
            );
            return;
        }
    }
    return if (! $cfg->{done});
    return if (! $cfg->{transfer});

    my $email
        = length $cfg->{email}       ? $cfg->{email}
        : length $cfg->{galaxy_user} ? $cfg->{galaxy_user}
        : undef;

    if (defined $email && ! Email::Valid->address($email)) {
        logger(
            "User provided invalid email address ($email)",
            $ADMIN_EMAIL,
        );
    }

    my $path = $cfg->{path};
    if (! length $path) {
        logger(
            "ERROR: no path defined in $fn",
            $ADMIN_EMAIL,
        );
        return;
    }
    die "No backtracking allowed in path\n"
        if ($path =~ /\.\./);

    my $file = $cfg->{file};
    if (! length $file) {
        logger(
            "ERROR: no file defined in $fn",
            $ADMIN_EMAIL,
        );
        return;
    }

    if ($file =~ /[\\\/\&\|\;]/) {
        logger(
            "ERROR: invalid filename $file",
            $ADMIN_EMAIL,
        );
        return;
    }
        
    my $md5 = $cfg->{md5};
    if (open my $input, '<:raw', $DIR_IN . "/$path$file") {

        my $digest = Digest::MD5->new();
        $digest->addfile($input);
        if ($digest->hexdigest() ne $md5) {
            logger(
                "Bad digest for $file",
                $ADMIN_EMAIL,
            );
            return;
        }

    }
    else {
        logger(
            "Error opening file " . $DIR_IN . "/$path$file: $!",
            $ADMIN_EMAIL,
        );
        return;
    }

    my $out_path = join '/',
        $DIR_OUT,
        $path;

    if (! -e $out_path) {
        if (! make_path($out_path) ) {
            logger(
                "ERROR creating path $out_path",
                $ADMIN_EMAIL,
            );
            return;
        }
    }
    elsif (! -d $out_path) {
        logger(
            "ERROR: $out_path exists but is not a directory",
            $ADMIN_EMAIL,
        );
        return;
    }

    if (-e "$out_path$file") {
        logger(
            "WARNING: $out_path$file exists and will not be overwritten",
            $email,
        );
        return;
    }

    say "cp ", $DIR_IN, "/$path$file => ", "$out_path$file";

    if (! copy( $DIR_IN . "/$path$file" => "$out_path$file" ) ) {
        logger(
            "ERROR copying $file: $!",
            $ADMIN_EMAIL,
        );
        return;
    }
        
    logger(
        "Successfully transferred $path$file",
        $email,
    );
    
}

sub logger {

    my ($msg, $email) = @_;

    $msg =  join "\t",
        localtime()->datetime(),
        $msg;

    # print to log

    open my $log, '>>', $LOGFILE
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} $msg;
    close $log;


    # send email if any valid addresses given

    $email //= $ADMIN_EMAIL;

    return if (! defined $email);
    
    my $cc = $ADMIN_EMAIL ne $email
        ? $ADMIN_EMAIL
        : undef;
        
    my $sender = "thermo_watcher@" . hostfqdn();

    my $smtp = Net::SMTP->new('localhost','Debug'=>0)
        or return;
    $smtp->mail($sender);
    $smtp->to($email);
    $smtp->bcc($cc) if (defined $cc);

    $smtp->data();
    $smtp->datasend("To: $email\n");
    $smtp->datasend("From: $sender\n");
    $smtp->datasend("Subject: thermo_watcher notification\n");
    $smtp->datasend("\n");
    $smtp->datasend($msg);
    $smtp->dataend();

    $smtp->quit();

}

