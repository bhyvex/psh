package Psh2::Parser;

use strict;

# constants
sub T_END() { 0; }
sub T_WORD() { 1; }
sub T_PIPE() { 2; }
sub T_REDIRECT() { 3; }
sub T_BACKGROUND() { 4; }
sub T_OR() { 5; }
sub T_AND() { 6; }

sub T_EXECUTE() { 1; }

# generate and cache regexpes
my %quotehash= qw|' ' " " q[ ] qq[ ]|;
my %quotedquotes= ("'" => "\'", "\"" => "\\\"", 'q[' => "\\]",
		   'qq[' => "\\]");
my %nesthash=  qw|( ) { } [ ]|;

my $part2= '\\\'|\\"|q\\[|qq\\[';
my $part1= '(\\n|\\s+|\\|\\||\\&\\&|\\||;;|;|\&>|\\&|>>|>|<|=|\\(|\\)|\\{|\\}|\\[|\\])';
my $regexp= qr[^((?:[^\\\\]|\\\\.)*?)(?:$part1|($part2))(.*)$]s;

############################################################################
##
## Split up lines into handy parts
##
############################################################################

sub decompose {
    my $line= shift;

    if ($line=~/^[a-zA-Z0-9]*$/ and index($line,"\n")==-1) { # perl 5.6 bug
	return [$line];
    }

    my @pieces= ('');
    my $start_new_piece= 0;

    while ($line) {
	if ($start_new_piece) {
	    push @pieces, '';
	    $start_new_piece= 0;
	}

	my ($prefix, $delimiter, $quote, $rest) =
	    $line=~ $regexp;

	if (defined $delimiter) {
	    $pieces[$#pieces] .= $prefix;
	    if (length($pieces[$#pieces])) {
		push @pieces, $delimiter;
	    } else {
		$pieces[$#pieces]= $delimiter;
	    }
	    $start_new_piece= 1;
	    $line= $rest;
	} elsif (defined $quote) {
	    my ($rest_of_quote, $remainder);
	    if ($quote eq 'qq[' or $quote eq '"') {
		($rest_of_quote, $remainder)=
		  ($rest =~ m/^((?:[^\\]|\\.)*?)$quotedquotes{$quote}(.*)$/s);
	    } elsif ($quote eq "'") {
		($rest_of_quote, $remainder)=
		  ($rest =~ m/^((?:[^\']|\'\')*)\'(.*)$/s);
	    } else {
		($rest_of_quote, $remainder)=
		  ($rest =~ m/^(.*?)$quotedquotes{$quote}(.*)$/s);
	    }
	    if (defined $rest_of_quote) {
		$pieces[$#pieces]= join('', $pieces[$#pieces], $prefix, $quote,
					$rest_of_quote, $quotehash{$quote});
		$line= $remainder;
	    } else { # can't find matching quote, give up
		die "parse: needmore: quote: missing $quote";
	    }
	} else {
	    last;
	}
    }
    if (length($line)) {
	$pieces[$#pieces].= $line;
    }

    my @realpieces= ();
    my @open= ();
    my @tmp= ();

    foreach my $piece (@pieces) {
	if (length($piece)==1) {
            if ($piece eq '[' or $piece eq '(' or $piece eq '{') {
                push @open, $piece;
            } elsif ($piece eq '}' or $piece eq ')' or $piece eq ']') {
                my $tmp= pop @open;
                if (!defined $tmp) {
                    die "parse: needmore: nest: closed $piece";
                }
                if ($nesthash{$tmp} ne $piece) {
                    die "parse: needmore: nest: wrong $tmp $piece";
                }
            }
        }
        if (@open) {
            push @tmp, $piece;
        } elsif (@tmp) {
	    push @realpieces, join('', @tmp, $piece);
	    @tmp= ();
	} else {
	    if ($piece=~/^\s+$/ and $piece ne "\n") {
		next;
	    }
            push @realpieces, $piece;
        }
    }
    if (@open) {
	die "parse: needmore: nest: missing @open";
    }
    return \@realpieces;
}

sub _remove_backslash {
    my $text= shift;

    $$text=~ s/\\\\/\001/g;
    $$text=~ s/\\t/\t/g;
    $$text=~ s/\\n/\n/g;
    $$text=~ s/\\r/\r/g;
    $$text=~ s/\\f/\f/g;
    $$text=~ s/\\b/\b/g;
    $$text=~ s/\\a/\a/g;
    $$text=~ s/\\e/\e/g;
    $$text=~ s/\\(0[0-7][0-7])/chr(oct($1))/ge;
    $$text=~ s/\\(x[0-9a-fA-F][0-9a-fA-F])/chr(oct($1))/ge;
    $$text=~ s/\\(.)/$1/g;
    $$text=~ s/\001/\\/g;
}

sub _unquote {
    my $text= shift;

    if (substr($$text,0,1) eq '\'' and
	substr($$text,-1,1) eq '\'') {
	$$text= substr($$text,1,-1);
    } elsif ( substr($$text,0,1) eq "\"" and
	      substr($$text,-1,1) eq "\"") {
	$$text= substr($$text,1,-1);
    } elsif ( substr($$text,0,2) eq 'q[' and
	      substr($$text,-1,1) eq ']') {
	$$text= substr($$text,2,-1);
    } elsif ( substr($$text,0,3) eq 'qq[' and
	      substr($$text,-1,1) eq ']') {
	$$text= substr($$text,3,-1);
    }
}

sub ungroup {
    my $text= shift;
    if (substr($text,0,1) eq '(' and
	substr($text,-1,1) eq ')') {
	return substr($text,1,-1);
    } elsif (substr($text,0,1) eq '{' and
	     substr($text,-1,1) eq '}') {
	return substr($text,1,-1);
    }
    return $text;
}

############################################################################
##
## Convert line pieces into tokens
##
############################################################################

sub _parse_fileno {
    my ($parts, $fileno)= @_;
    my $bothflag= 0;
    while (@$parts>0) {
	my $tmp= shift @$parts;
	next if $tmp=~ /^\s+$/;
	if ($tmp=~ /^\[(.+?)\]$/) {
	    $tmp= $1;
	    my @tmp= split('=', $tmp);
	    if (@tmp>2) {
		die "parse: fileno: more than one = sign";
	    }
	    if (@tmp<2) {
		push @tmp, $fileno->[1];
	    }
	    if (@tmp==2 and !$tmp[0]) {
		$tmp[0]= $fileno->[0];
	    }
	    my @result=();
	    foreach (@tmp) {
		no strict 'refs';
		if (lc($_) eq 'all') {
		    $_= 1;
		    $bothflag= 1;
		}
		if (/^\d+$/) {
		    push @result, $_+0;
		} else {
		    # TODO: Add Perl Filehandle access
		}
	    }
	    @$fileno= @result;
	} else {
	    unshift @$parts, $tmp;
	}
	last;
    }
    return $bothflag;
}

sub make_tokens {
    my $line= shift;
    my @parts= @{decompose($line)};
    my @tmp= ();
    my @tokens= ();
    my $tmp;
    while (defined ($tmp= shift @parts)) {
	if ($tmp eq '||' or $tmp eq '&&') {
	    push @tokens, @tmp;
	    push @tokens, [T_END], [ $tmp eq '||'? T_OR: T_AND ];
	    @tmp= ();
	} elsif ($tmp eq ';;') {
	    push @tmp, [T_WORD, ';'];
	} elsif ($tmp eq '|') {
	    my @fileno= (1,0);
	    my $bothflag= 0;
	    $bothflag ||= _parse_fileno(\@parts, \@fileno);
	    push @tokens, [ T_REDIRECT, '>&', $fileno[0], 'chainout'];
	    if ($bothflag) {
		push @tokens, [ T_REDIRECT, '>&', 2, $fileno[0]];
	    }
	    push @tokens, @tmp;
	    push @tokens, [ T_PIPE ];
	    @tmp= ( [T_REDIRECT, '<&', $fileno[1], 'chainin']);
	} elsif ($tmp eq '>' or $tmp eq '>>' or
		 $tmp eq '&>') {
	    my $bothflag= 0;
	    if ($tmp eq '&>') {
		$bothflag= 1;
		$tmp= '>';
	    }
	    my @fileno= (1,0);
	    my $file;

	    $bothflag ||= _parse_fileno(\@parts, \@fileno);
	    if ($fileno[1]==0) {
		while (@parts>0) {
		    $file= shift @parts;
		    last if $file !~ /^\s+$/;
		    $file= '';
		}
		die "parse: redirection >: file missing" unless $file;
		push @tmp, [T_REDIRECT, $tmp, $fileno[0], $file];
	    } else {
		push @tmp, [T_REDIRECT, '>&', @fileno];
	    }
	    if ($bothflag) {
		push @tmp, [T_REDIRECT, '>&', 2, $fileno[0]];
	    }
	} elsif ($tmp eq '<') {
	    my $file;
	    my @fileno= (0,0);
	    _parse_fileno(\@parts, \@fileno);
	    if ($fileno[0]==0) {
		while (@parts>0) {
		    $file= shift @parts;
		    last if $file !~ /^\s+$/;
		    $file= '';
		}
		die "parse: redirection <: file missing" unless $file;
		push @tmp, [T_REDIRECT, '<', $fileno[1], $file];
	    } else {
		push @tmp, [T_REDIRECT, '<&', $fileno[1], $fileno[0]];
	    }
	} elsif ($tmp eq '&') {
	    push @tokens, @tmp;
	    push @tokens, [T_BACKGROUND], [T_END];
	    @tmp= ();
	} elsif ($tmp eq ';' or $tmp eq "\n") {
	    push @tokens, @tmp;
	    push @tokens, [T_END];
	    @tmp= ();
	} else {
	    if (substr($tmp,0,2) eq "qq[" or
	        substr($tmp,0,1) eq '"') {
		_remove_backslash(\$tmp);
	    } elsif (substr($tmp,0,1) eq "'") {
		substr($tmp,1,-1)=~ s/\'\'/\'/g;
	    }
	    _unquote(\$tmp);
	    push @tmp, [ T_WORD, $tmp];
	}
    }
    push @tokens, @tmp;
    return \@tokens;
}

sub parse_line {
    my $line= shift;
    my $psh= shift;

    return [] if substr( $line, 0, 1) eq '#' or $line=~/^\s*$/;

    my $tokens= make_tokens( $line );
    my @elements= ();
    my $element;
    while ( @$tokens > 0 ) {
	$element= _parse_complex( $tokens, $psh);
	return undef unless defined $element; # TODO: Error handling
	push @elements, $element;
	if (@$tokens > 0) {
	    if ($tokens->[0][0] == T_END) {
		shift @$tokens;
	    }
	    if (@$tokens > 0) {
		if ($tokens->[0][0] == T_AND) {
		    shift @$tokens;
		    push @elements, [ T_AND ];
		} elsif ($tokens->[0][0] == T_OR) {
		    shift @$tokens;
		    push @elements, [ T_OR ];
		}
	    }
	}
    }
    return \@elements;
}

sub _parse_complex {
    my $tokens= shift;
    my $psh= shift;
    my $piped= 0;
    my $fg= 1;
    return [ T_EXECUTE, $fg, @{_sub_parse_complex($tokens, \$piped, \$fg, {}, $psh )}];
}

sub _sub_parse_complex {
    my ($tokens, $piped, $fg, $alias_disabled, $psh)= @_;
    my @simple= _parse_simple( $tokens, $piped, $fg, $alias_disabled, $psh);

    while (@$tokens > 0 and $tokens->[0][0] == T_PIPE ) {
	shift @$tokens;
	$$piped= 1;
	push @simple, _parse_simple( $tokens, $piped, $fg, $alias_disabled, $psh);
    }

    if (@$tokens > 0 and $tokens->[0][0] == T_BACKGROUND ) {
	shift @$tokens;
	$$fg= 0;
    }
    return \@simple;
}

sub _is_precommand {
    my $word= shift;
    return 1 if $word eq 'noglob' or $word eq 'noexpand'
      or $word eq 'noalias' or $word eq 'nobuiltin' or
	$word eq 'builtin';
}

sub _parse_simple {
    my ($tokens, $piped, $fg, $alias_disabled, $psh)= @_;
    my (@words, @options, @savetokens, @precom);
    my $opt= {};

    my $firstwords= 1;

    while (@$tokens > 0 and
	  ($tokens->[0][0] == T_WORD or
	   $tokens->[0][0] == T_REDIRECT )) {
	my $token= shift @$tokens;
	if ($token->[0] == T_WORD) {
	    if ($firstwords and
		_is_precommand($token->[1])) {
		push @precom, $token;
		$opt->{$token->[1]}= 1;
	    } else {
		$firstwords= 0;
		push @savetokens, $token;
		push @words, $token->[1];
	    }
	} elsif ($token->[0] == T_REDIRECT) {
	    push @options, $token;
	}
    }

    return () if !@words or (@words==1 and $words[0] eq '');

    if (!$opt->{noalias} and $psh->{aliases} and
        $psh->{aliases}->{$words[0]} and
        !$alias_disabled->{$words[0]}) {
	my $alias= $psh->{aliases}->{$words[0]};
	$alias_disabled->{$words[0]}= 1;
	my $tmp= make_tokens($alias);
	unshift @$tmp, @precom;
	shift @savetokens;
	push @$tmp, @savetokens;
	push @$tmp, @options;
	return @{_sub_parse_complex($tmp, $piped, $fg, $alias_disabled, $psh)};
    } elsif (substr($words[0],0,1) eq '\\') {
	$words[0]= substr($words[0],1);
    }

    my $line= join ' ', @words;
    $psh->{tmp}{options}= $opt;

    if ($words[0] and substr($words[0],-1) eq ':') {
	my $tmp= lc(substr($words[0],0,-1));
	if (exists $psh->{language}{$tmp}) {
	    eval 'use Psh2::Language::'.ucfirst($tmp);
	    if ($@) {
		print STDERR $@;
		# TODO: Error handling
	    }
	    return [ 'language', 'Psh2::Language::'.ucfirst($tmp), \@options, \@words, $line, $opt];
	} else {
	    die "parse: unsupported language $tmp";
	}
    }

    @words= @{glob_expansion($psh, \@words)} unless $opt->{noglob};

    unless ($opt->{nobuiltin}) {
	my $tmp;
	if ($tmp= $psh->is_builtin($words[0])) {
	    eval 'use Psh2::Builtins::'.ucfirst($tmp);
	    if ($@) {
		print STDERR $@;
		# TODO: Error handling
	    }
	    return [ 'builtin', 'Psh2::Builtins::'.ucfirst($tmp), \@options, \@words, $line, $opt];
	}
    }
    unless ($opt->{builtin}) {
	my $tmp= $psh->which($words[0]);
	if ($tmp) {
	    return [ 'execute', $tmp, \@options, \@words, $line, $opt];
	}
	foreach my $strategy (@{$psh->{strategy}}) {
	    my $tmp= eval {
		$strategy->applies(\@words, $line);
	    };
	    if ($@) {
		# TODO: Error handling
	    } elsif ($tmp) {
		return [ $strategy, $tmp, \@options, \@words, $line, $opt];
	    }
	}
    }
    eval "use Data::Dumper;";
    print STDERR Dumper(\@words);
    die "duh";
}

sub glob_expansion {
    my ($psh, $words)= @_;
    my @retval  = ();

    for my $word (@{$words}) {
	if (
	     (substr($word,0,1) eq '"' and substr($word,-1) eq '"') or
	     (substr($word,0,1) eq '`' and substr($word,-1) eq '`') or
	     (substr($word,0,1) eq "'" and substr($word,-1) eq "'") or
	     (substr($word,0,1) eq '(' and substr($word,-1) eq ')') or
	     (substr($word,0,1) eq '{' and substr($word,-1) eq '}') or
	     $word !~ m/\[.*\]|[*?~]/
	   ) {
	    push @retval, $word;
	} else {
	    my @results = $psh->glob($word);
	    if (scalar(@results) == 0) {
		push @retval, $word;
	    } else {
		push @retval, @results;
	    }
	}
    }
    return \@retval;
}


1;