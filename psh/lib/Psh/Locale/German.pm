package Psh::Locale::German;

use strict;
use vars qw($VERSION);
use locale;

$VERSION = '0.01';

BEGIN {
	my %sig_description = (
							'TTOU' => 'Terminalausgabe',
							'TTIN' => 'Terminaleingabe',
							'KILL' => 'gewaltsam beendet',
							'FPE'  => 'Flie�kommaausnahme',
							'SEGV' => 'Unerlaubter Speicherzugriff',
							'PIPE' => 'Pipe unterbrochen',
							'BUS'  => 'Bus Fehler',
							'ABRT' => 'Unterbrochen',
							'ILL'  => 'Illegale Anweisung',
							'TSTP' => 'von Benutzer unterbrochen'
							);
	$psh::text{sig_description}=\%sig_description;

}



1;
__END__

=head1 NAME

Psh::Locale::German - containing translations for German locales

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 AUTHOR

Markus Peter, warp@spin.de

=head1 SEE ALSO


=cut