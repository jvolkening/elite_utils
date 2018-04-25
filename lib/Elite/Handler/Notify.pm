package Elite::Handler::Notify;

use strict;
use warnings;
use 5.012;

use Array::Utils qw/array_minus/;
use Email::Valid;
use Net::Domain qw/hostfqdn/;
use Paws;

sub run {

    my ($class, %args) = @_;

    for (qw/config/) {
        die "Parameter $_ must be defined\n"
            if (! defined $args{$_});
    }

    my $self = bless {} => $class;
    for (keys %{$args{config}}) {
        $self->{$_} = $args{config}->{$_};
    }

    my @candidates = split /,\s*/, $self->{notify};
    my @sms_candidates = (
        grep {$_ !~ /[^\+\d\-\s\(\)\.]/} @candidates
    );
    my @email_candidates = (
        grep {Email::Valid->address($_)} @candidates
    );

    my @used;

    my $msg =
        "This is an automated notification from the $self->{_machine_name}."
    . " The following run has now completed:\n\n$self->{file}";
    my $subject = "$self->{_machine_name} notification";

    push @used, $self->email( $msg, $subject, @email_candidates );
    push @used, $self->sms(   $msg, $subject, @sms_candidates   );

    return(
        [@used],
        [array_minus(@candidates, @used)],
    );

}

sub email {

    my ($self, $msg, $subject, @candidates) = @_;

    my @used;

    for my $candidate (@candidates) {
        if ( _send_email($candidate, $subject, $msg) ) {
            push @used, $candidate;
        }
    }

    return @used;

}

sub sms {

    my ($self, $msg, $subject, @candidates) = @_;

    my @used;

    for my $candidate (@candidates) {

        my $parsed = $candidate;
        $parsed =~ s/[\-\s\(\)\.]//g;

        if ($parsed !~ /^\+/) {
            # assume US country code
            $parsed = $self->{_default_country} . $parsed;
        }

        next if ($parsed !~ /^\+\d+$/);
        next if (length($parsed) < 7 || length($parsed) > 16);

        if ( _send_sms(
            $parsed,
            $self->{_sns_region},
            $subject,
            $msg,
        ) ) {
            push @used, $candidate;
        }

    }

    return @used;
            
}

sub _send_sms {

   my ($number, $region, $subject, $msg) = @_; 

    my $ua = Paws->service('SNS', region => $region)
        or die "Failed to connect to AWS SNS: $!\n"; 

    my $resp = $ua->Publish(
        Message     => $msg,
        PhoneNumber => $number,
        Subject     => $subject,
    ) or return 0;

    my $msg_id = $resp->MessageId
        or return 0;

    return 1;

}

sub _send_email {

    my ($recipient, $subject, $msg) = @_;

    my $sender = "thermo_watcher@" . hostfqdn();

    my $smtp = Net::SMTP->new('localhost','Debug'=>0)
        or return 0;
    $smtp->mail($sender);
    $smtp->to($recipient);

    $smtp->data();
    $smtp->datasend("To: $recipient\n");
    $smtp->datasend("From: $sender\n");
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("\n");
    $smtp->datasend($msg);
    $smtp->dataend();

    $smtp->quit();

    return 1;

}


1;
