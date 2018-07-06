use 5.012;

use strict;
use warnings;
use Module::Build;
use Config;

my $builder = Module::Build->new(
    module_name        => 'Thermo::Handler',
    license            => 'GPL_3',
    dist_author        => q{Jeremy Volkening <jdv@base2bio.com>},
    dist_abstract      => q{Utilities for automating data transfer from an Orbitrap},
    configure_requires => {
        'Config'        => 0,
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Try::Tiny'       => 0,
        'Config::Tiny'    => 0,
        'Email::Valid'    => 0,
        'Linux::Inotify2' => 0,
        'Net::Domain'     => 0,
        'Net::SMTP'       => 0,
        'Array::Utils'    => 0,
    },
    meta_merge => {
        resources => {
            repository => 'https://github.com/jvolkening/elite_utils'
        }
    },
    add_to_cleanup => [ 'Thermo-Handler-*' ],
    create_license => 1,
);
$builder->create_build_script;
