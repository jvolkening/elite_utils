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
my @msconvert_args = (
    '--mzML',
    '--numpressAll',
    '--noindex',
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

    # sometimes file is read before it is done being written
    my $size = -s $fn_new;
    for (1..20) {
        sleep 5;
        last if ($size == -s $fn_new);
    }

    open my $in, '<', $fn_new or die "Error opening $fn_new: $!\n";

    my $user = <$in>;
    chomp $user;
    my $date = <$in>;
    chomp $date;
    my $line = <$in>;
    chomp $line;

    my ($fn_raw, $type, $md5) = split "\t", $line;
    next LOOP if (! defined $type || $type ne 'raw');

    if (length($user) > 16 || $user =~ /[^\w\.\-]/) {
        logger("Bad username ($user) for $fn_new");
        next LOOP;
    }
    if (! -e "$TARGET/$fn_raw") {
        logger("File not found: $TARGET/$fn_raw" );
        next LOOP;
    }

    if (open my $raw, '<', "$TARGET/$fn_raw") {

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
        
    my $ret = system(
        'msconvert',
        @msconvert_args,
        '--outdir' => "\"$TARGET\"",
        "\"$TARGET/$fn_raw\""
    );
    if ($ret) {
        logger( "msconvert failed for $fn_raw" );
        next LOOP;
    }

    my $fn_mzml = basename($fn_raw);
    $fn_mzml =~ s/\.raw$/\.mzML/i;

    my $mzml_digest;
    if ( open my $mzml, '<', "$TARGET/$fn_mzml" ) {
        my $digest = Digest::MD5->new();
        $digest->addfile($mzml);
        $mzml_digest = $digest->hexdigest;
    }
    else {
        logger("Error opening mzML file $TARGET/$fn_mzml: $!" );
        next LOOP;
    }

    if (-e "$TARGET/$fn_mzml.ready") {
        logger( "found existing ready file $fn_mzml.ready" );
        next LOOP;
    }

    if (open my $ready, '>', "$TARGET/$fn_mzml.ready") {
        say {$ready} $user;
        say {$ready} localtime()->datetime;
        say {$ready} join "\t",
            $fn_mzml,
            'mzml',
            $mzml_digest;
        close $ready;
    }
    else {
        logger( "Error opening ready file for $fn_mzml: $!" );
        next LOOP;
    }

    logger( "Successfully converted $fn_raw" );

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

END {

    $queue->enqueue(undef);
    $worker->join();
}
