package Elite::Handler::MGF;

use strict;
use warnings;
use 5.012;

use parent 'Elite::Handler::Converter';

sub suffix {return 'mgf'}

sub params { return
    [
        '--mgf',
    ];
}

1;
