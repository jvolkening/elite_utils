#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Bio::Galaxy::API;
use Email::Valid;
use Net::SMTP::SSL;
use Getopt::Long;

my $name;
my $email;
my $server;
my $org = 'local';
my $pw_len = 10;
my @cc;

GetOptions(
    'name=s'   => \$name,
    'email=s'  => \$email,
    'server=s' => \$server,
    'org=s'    => \$org,
    'pw_len=i' => \$pw_len,
    'cc=s'     => \@cc,
);

# validation
die "missing name or email\n"
    if (! defined $name || ! defined $email);

die "Bad email\n"
    if (! Email::Valid->address($email));

my $pw = random_pw( $pw_len );

create_galaxy_user($name, $email, $pw);
send_mail($name, $email, $pw, @cc);

exit;

sub create_galaxy_user {

}

sub send_mail {

    my ($name, $email, $pw, @cc) = @_;

    my $msg = generate_email_text($name, $email, $pw);
    say "$msg";

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

    my ($name, $mail, $pw) = @_;

    return <<"MAIL";
$name,

An account has been created for you on the $org Galaxy server. Your username
is your email address (all lowercase) and your password is:

$pw

Please change your password after logging in for the first time. If you have
any questions or have problems logging in, please let me know.

Regards,
Jeremy
MAIL

}



