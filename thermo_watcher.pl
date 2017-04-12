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
use constant OUT => "$ENV{HOME}/shared";
use constant LOG => "$ENV{HOME}/transfer.log";

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
        $cfg = Config::Tiny->read($fn)->{_};
        last if ($cfg->{done});
        sleep 2;
    }
    return if (! $cfg->{done});

    my $user = $cfg->{user};
    if (! defined $user) {
        logger( "ERROR: no user defined in $fn" );
        return;
    }
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
    if (open my $input, '<', IN . "/$file") {

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

    my $out_path = join '/',
        OUT,
        $user,
        localtime()->ymd();
    if (! -e $out_path) {
        if (! make_path($out_path) ) {
            logger( "ERROR creating path $out_path" );
            return;
        }
    }
    elsif (! -d $out_path) {
        logger( "ERROR: $out_path exists but is not a directory" );
        return;
    }

    say "cp ", IN, "/$file => ", "$out_path/$file";

    if (-e "$out_path/$file") {
        logger( "WARN: $out_path/$file exists and won't overwrite" );
        return;
    }

    if (! copy( IN . "/$file" => "$out_path/$file" ) ) {
        logger( "ERROR copying $file: $!" );
        return;
    }
        
    logger( "Successfully transfered $file" );
        
    
}

sub logger {

    my ($msg) = @_;

    open my $log, '>>', LOG
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} join "\t",
        localtime()->datetime(),
        $msg;

}

