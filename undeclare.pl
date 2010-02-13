#!/usr/bin/perl

# A simple tool for translating MooseX::Method::Signatures syntax sugar
# into native subs and parameters parsing
# Motivation: http://www.mail-archive.com/moose@perl.org/msg01220.html
#
# Authors and contributors: Oleg Komarov, Vladimir Kim
# Last update: 2010-02-13

use strict;
use warnings;

use Undeclare qw( undeclare undeclareFile );

if( my $InputFileName = $ARGV[ 0 ] ) {
   my $OutputFileName = $ARGV[ 1 ] || $InputFileName;
   undeclareFile( $InputFileName, $OutputFileName );
}
else {
   print undeclare( join( '', <> ) );
}

exit;
