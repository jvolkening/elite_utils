#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Config::Tiny;
use Digest::MD5;
use File::Copy qw/copy/;
use File::Path qw/make_path/;
use Linux::Inotify2;
use Time::Piece;

use constant IN  => "$ENV{HOME}/incoming";
use constant LOG => "$ENV{HOME}/galaxy.log";

my $inotify = Linux::Inotify2->new()
    or die "Unable to create Inotify2 obj: $!\n";

$inotify->watch(
    IN,
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
            logger( "ERROR: failed to parse ready file $fn" );
            return;
        }
    }
    return if (! $cfg->{done});

    # don't bother if galaxy_user not defined
    return if (! length $cfg->{galaxy_user});

    # don't bother if not mzML
    return if ($cfg->{type} ne 'mzml');

    my $path = $cfg->{path};
    if (! defined $path) {
        logger( "ERROR: no path defined in $fn" );
        return;
    }
    die "No backtracking allowed in path\n"
        if ($path =~ /\.\./);

    my $file = $cfg->{file};
    if (! defined $file) {
        logger( "ERROR: no file defined in $fn" );
        return;
    }

    if ($file =~ /[\\\/\&\|\;]/) {
        logger( "ERROR: invalid filename $file" );
        return;
    }
        
    my $md5 = $cfg->{md5};
    if (open my $input, '<:raw', IN . "/$path$file") {

        my $digest = Digest::MD5->new();
        $digest->addfile($input);
        if ($digest->hexdigest() ne $md5) {
            logger( "Bad digest for $file" );
            return;
        }

    }
    else {
        logger("Error opening file " . IN . "/$file: $!" );
        return;
    }

    # Sanitize galaxy user name
    my $user = $cfg->{galaxy_user};
    if ($user =~ /[^\w\@\.\-]/) {
        logger("Bad galaxy username: $user" );
        return;
    }
      
    #-----------------------------#
    #TODO: Do Galaxy upload here
    #-----------------------------#
    
}

sub logger {

    my ($msg) = @_;

    open my $log, '>>', LOG
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} join "\t",
        localtime()->datetime(),
        $msg;

}

