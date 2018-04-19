#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Bio::Galaxy::API;
use Config::Tiny;
use Digest::MD5;
use File::Copy qw/copy/;
use File::Path qw/make_path/;
use Linux::Inotify2;
use Time::Piece;
use List::Util qw/first/;

use constant IN  => "$ENV{HOME}/incoming";
use constant LOG => "$ENV{HOME}/galaxy.log";
use constant MAX_TRIES => 6;

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

    my $user = $cfg->{galaxy_user};

    # don't bother if galaxy_user not defined
    return if (! defined $user || ! length $user);

    # Sanitize galaxy user name
    if ($user =~ /[^\w\@\.\-]/) {
        logger("ERROR: Bad galaxy username: $user" );
        return;
    }

    my $workflow = $cfg->{galaxy_workflow};

    # don't bother if no workflow defined
    return if (! defined $workflow || ! length $workflow);

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
            logger( "ERROR: Bad digest for $file" );
            return;
        }

    }
    else {
        logger("ERROR opening file " . IN . "/$file: $!" );
        return;
    }

      
    #-----------------------------#
    #TODO: Do Galaxy upload here
    #-----------------------------#

    my $dataset = galaxy_upload(
        $user,
        $path,
        $file,
    );
    if (defined $dataset) {
        logger("Successfully uploaded file $file to $user:$path");
    }
    else {
        return;
    }

    # 'upload' workflow is special case and not actual workflow name
    return if ($workflow =~ /^upload$/i);

    my $ok = galaxy_run(
        $user,
        $workflow,
        $dataset,
    );
    if ($ok) {
        logger("Successfully submitted $file to workflow $user:$workflow");
    }
       
    return;
    
}

sub logger {

    my ($msg) = @_;

    open my $log, '>>', LOG
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} join "\t",
        localtime()->datetime(),
        $msg;

}

sub galaxy_upload {

    my ($user, $path, $file) = @_;

    my $ua = Bio::Galaxy::API->new(
        url => 'http://localhost:8080',
        check_secure => 0,
    );
        
    my $lib = first {
        $_->name() eq $user
    } $ua->libraries;

    if (! defined $lib) {
        logger("ERROR: No personal library found for $user");
        return undef;
    }

    my $parent = $lib->add_folder(
        path => 'elite_data',
    );
    if (! defined $parent) {
        logger("ERROR: Failed to add/find upload folder for $user");
        return undef;
    }

    my $dataset = $lib->add_file(
        path   => "$path$file",
        file   => IN . "/$path$file",
        parent => $parent->id,
    );
    if (! defined $dataset) {
        logger("ERROR: Failed to upload file $file for $user");
        return undef;
    }
    elsif ($dataset == 0) {
        logger("ERROR: file $file already exists on Galaxy for $user");
        return undef;
    }

    return $dataset;

}

sub galaxy_run {

    my ($user, $workflow, $dataset) = @_;

    my $ua = Bio::Galaxy::API->new(
        url => 'http://localhost:8080',
        check_secure => 0,
    );

    my $wf = first {
        lc( $_->name() ) eq lc( $workflow )
    } $ua->workflows;

    if (! defined $wf) {
        logger("ERROR: No workflow named $workflow found for $user");
        return 0;
    }

    my $data_name = $dataset->name;

    my $invoc = $wf->run(
        history     => "workflow \"$workflow\" on \"$data_name\"",
        ds_map      => {
            0 => {
                id => $dataset->id,
                src => 'ld'
            },
        }
    );

    if (! defined $invoc) {
        logger("ERROR: Failed to invoke $workflow on $data_name for $user");
        return 0;
    }

    for (1..MAX_TRIES) {
        return 1 if ($invoc->{state} eq 'scheduled');
        sleep 10;
        $invoc->update();
    }

    logger("ERROR: Timeout waiting for $workflow (on $data_name for $user");
    return 0;

}
