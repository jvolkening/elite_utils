# msconvert_watcher.pl
#
# copyright 2017 Jeremy Volkening, UW-Madison
#
# Usage: msconvert_watcher.pl [target_dir]

use strict;
use warnings;
use 5.012;

use Digest::MD5;
use File::Basename qw/basename/;
use threads;
use Thread::Queue;
use Time::Piece;
use Win32::ChangeNotify;

my $BASE = $ARGV[0] // "T:/";

# configure msconvert
my @msconvert_mzml_args = (
    '--mzML',
    '--numpressAll',
    '--noindex',
    '--filter' => '"peakPicking true 1-"',
    '--filter' => '"defaultArrayLength 2-"',
);
my @msconvert_mgf_args = (
    '--mgf',
    '--filter' => '"peakPicking true 1-"',
    '--filter' => '"defaultArrayLength 2-"',
);

my $TARGET = "$BASE/incoming";
die "No target found (check that share is mounted and 'incoming' exists)\n"
    if (! -d $TARGET);
my $LOG = "$BASE/convert.log";

my $queue  = Thread::Queue->new;
my $worker = threads->create(\&process);

my $notify = Win32::ChangeNotify->new( $TARGET, 0, 'FILE_NAME' );

# track previously seen filenames
my %last;
@last{ glob "$TARGET/*.ready" } = ();


print "msconvert monitor running (do not close)...\n";


LOOP:
while (1) {

    my $r = $notify->wait( 10_000 );
    exit if (! defined $r || $r < 0);
    next if ($r != 1);
    $notify->reset;

    # if we get here, something has changed
    my @files = glob "$TARGET/*.ready";
    my @new = ();
    if ( scalar @files > scalar keys %last ) {
        my %temp;
        @temp{ @files } = ();
        delete @temp{ keys %last };
        @new = keys %temp;
    }
    undef %last;
    @last{ @files } = ();

    $queue->enqueue( @new );

}

sub process {

  LOOP:
  while (defined( my $fn_new = $queue->dequeue )) {

    my $cfg;
    for (1..10) {
        $cfg = Config::Tiny->read($fn_new)->{_};
        last if ($cfg->{done});
        sleep 2;
    }
    next LOOP if (! $cfg->{done});

    open my $in, '<', $fn_new or die "Error opening $fn_new: $!\n";

    my $user   = $cfg->{user};
    my $fn_raw = $cfg->{file};
    my $type   = $cfg->{type};
    my $mzml   = $cfg->{mzml};
    my $mgf    = $cfg->{mgf};
    my $md5    = $cfg->{md5};

    next LOOP if (! defined $type || $type ne 'raw');
    next LOOP if (! $mzml && ! $mgf);

    if (length($user) > 16 || $user =~ /\W/) {
        logger("ERROR: Bad username ($user) for $fn_new");
        next LOOP;
    }
    if ($fn_raw =~ /[\\\/\&\|\;]/) {
        logger( "ERROR: invalid filename $fn_raw" );
        next LOOP;
    }
    if (! -e "$TARGET/$fn_raw") {
        logger("File not found: $TARGET/$fn_raw" );
        next LOOP;
    }

    if (open my $raw, '<:raw', "$TARGET/$fn_raw") {

        my $digest = Digest::MD5->new();
        $digest->addfile($raw);
        if ($digest->hexdigest() ne $md5) {
            logger( "Bad digest for $fn_raw" );
            next LOOP;
        }

    }
    else {
        logger("Error opening raw file $TARGET/$fn_raw: $!" );
        next LOOP;
    }

    convert( $fn_raw, 'mzml', 'mzML', \@msconvert_mzml_args );
        if ($mzml);
    convert( $fn_raw, 'mgf', 'mgf', \@msconvert_mgf_args );
        if ($mzml);

  }

}

sub logger {

    my ($msg) = @_;

    open my $log, '>>', $LOG
        or die "ERROR: failed to open log for writing: $!\n";
    say {$log} join "\t",
        localtime()->datetime(),
        $msg;
    close $log;

}

sub convert {

    my ($fn_raw, $type, $suffix, $arg_ref) = @_;

    my $fn_conv = basename($fn_raw);
    $fn_conv =~ s/\.raw$/\.$suffix/i;
    if (-e "$TARGET/$fn_conv") {
        logger("File $fn_conv already exists and won't overwrite\n");
        next LOOP;
    }
        
    my $ret = system(
        'msconvert',
        @{$arg_ref},
        '--outdir' => "\"$TARGET\"",
        "\"$TARGET/$fn_raw\""
    );
    if ($ret) {
        logger( "msconvert to $type failed for $fn_raw" );
        next LOOP;
    }

    my $conv_digest;
    if ( open my $conv, '<:raw', "$TARGET/$fn_conv" ) {
        my $digest = Digest::MD5->new();
        $digest->addfile($conv);
        $conv_digest = $digest->hexdigest;
    }
    else {
        logger("Error opening $type file $TARGET/$fn_conv: $!" );
        next LOOP;
    }

    if (-e "$TARGET/$fn_conv.ready") {
        logger( "found existing ready file $fn_conv.ready" );
        next LOOP;
    }

    if (open my $ready, '>', "$TARGET/$fn_conv.ready") {
        say {$ready} "user=", $user;
        say {$ready} "time=", localtime()->datetime;
        say {$ready} "type=", $type;
        say {$ready} "md5=",  $conv_digest;
        say {$ready} "file=", $fn_conv;
        say {$ready} "done=", '1';
        close $ready;
    }
    else {
        logger( "Error opening ready file for $fn_conv: $!" );
        next LOOP;
    }

    logger( "Successfully converted $fn_raw" );


END {

    $queue->enqueue(undef);
    $worker->join();
}
