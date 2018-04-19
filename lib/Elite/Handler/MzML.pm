package Elite::Handler::MzML;

use strict;
use warnings;
use 5.012;

use parent 'Elite::Handler::Converter';

sub suffix {return 'mzML'}

sub params { return
    [
        '--mzML',
        '--numpressAll',
        '--filter' => 'peakPicking true 1-',
    ];
}

1;
