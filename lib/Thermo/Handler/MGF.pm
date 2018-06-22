package Thermo::Handler::MGF;

use strict;
use warnings;
use 5.012;

use parent 'Thermo::Handler::Converter';

sub suffix {return 'mgf'}

sub params { return
    [
        '--mgf',
    ];
}

1;
