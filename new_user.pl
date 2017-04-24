#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Bio::Galaxy::API;
use Email::Valid;
use Net::SMTP::SSL;
use Getopt::Long;
use Net::Domain qw/hostfqdn/;

my $name;
my $user;
my $email;
my $url;
my $org = 'local';
my $pw_len = 10;
my @cc;
my $template;

GetOptions(
    'name=s'     => \$name,
    'user=s'     => \$user,
    'email=s'    => \$email,
    'url=s'      => \$url,
    'org=s'      => \$org,
    'pw_len=i'   => \$pw_len,
    'cc=s'       => \@cc,
    'template=s' => \$template,
);

$url //= 'http://localhost:8080';

if (! defined $user) {
    $user = lc $name;
    $user =~ s/\s+/_/g;
    pos($user) = 0;
    $user =~ s/[^a-z0-9\_\-]/-/g;
    say "No username provided, using $user\n";
}

# validation
die "missing name or email\n"
    if (! defined $name || ! defined $email);

die "missing or unreadable mail template\n"
    if (! -r $template);

die "Bad email\n"
    if (! Email::Valid->address($email));

my $pw = random_pw( $pw_len );

#create_galaxy_user($user, $email, $pw, $url);
my $msg = generate_email_text(
    $template, $name, $user, $email, $org, $pw
);
send_mail($msg, $name, $email, $pw, @cc);

exit;

sub create_galaxy_user {

    my ($user, $email, $pw, $url) = @_;

    my $check_secure = $url eq 'http://localhost:8080'
        ? 0
        : 1;

    my $ua = Bio::Galaxy::API->new(
        url => $url,
        check_secure => $check_secure,
    );

    my $usr = $ua->new_user(
        user     => $user,
        email    => $email,
        password => $pw,
    );

    if (defined $usr) {
        say "Successfully created Galaxy user\n";
    }
    else {
        say "Error creating Galaxy user\n";
        exit;
    }

}

sub send_mail {

    my ($msg, $name, $email, $pw, @cc) = @_;

    my $sender = $ENV{USER} . '@' . hostfqdn();

    my $smtp = Net::SMTP->new('localhost')
        or die "Error starting SMTP session: $@\n";
    $smtp->mail($sender);
    $smtp->to($email);
    $smtp->cc(@cc);

    $smtp->data();
    $smtp->datasend("To: $email\n");
    $smtp->datasend("From: $sender\n");
    $smtp->datasend("Subject: Galaxy account creation\n");
    $smtp->datasend("\n");
    $smtp->datasend($msg);
    $smtp->dataend();

    $smtp->quit();

    say "Successfully send mail notification";
    
    return;

}

sub random_pw {

    my ($len) = @_;

    my @pw_chars = (
        'A'..'Z',
        'a'..'z',
        0..9,
        qw/! +/,
    );

    return join '', map {
        $pw_chars[ int(rand(scalar(@pw_chars))) ]
    } 1..$len;
        
}

sub generate_email_text {

    my ($template, $name, $user, $email, $org, $pw) = @_;

    my $msg;

    open my $tpl, '<', $template
        or die "Error opening template file: $!\n";

    warn "$name, $org, $pw\n";

    while (my $line = <$tpl>) {
        for my $token (
            [ 'NAME'  => $name  ],
            [ 'USER'  => $user  ],
            [ 'EMAIL' => $email ],
            [ 'ORG'   => $org   ],
            [ 'PW'    => $pw    ],
        ) {
            $line =~ s/<<<<$token->[0]>>>>/$token->[1]/;
        }
        $msg .= $line;
    }

    return $msg;

}
