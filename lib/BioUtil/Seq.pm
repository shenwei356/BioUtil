package BioUtil::Seq;

require Exporter;
@ISA    = (Exporter);
@EXPORT = qw(
    FastaReader
    read_sequence_from_fasta_file
    write_sequence_to_fasta_file
    format_seq

    validate_sequence
    revcom
    base_content
    dna2peptide
    codon2aa
    generate_random_seqence

    shuffle_sequences
    rename_fasta_header
    clean_fasta_header
);

use vars qw($VERSION);

use 5.010_000;
use strict;
use warnings FATAL => 'all';

use List::Util qw(shuffle);

=head1 NAME

BioUtil::Seq - Utilities for sequence

=head1 VERSION

Version 2014.0814

=cut

our $VERSION = 2014.0814;

=head1 EXPORT

    FastaReader
    read_sequence_from_fasta_file 
    write_sequence_to_fasta_file 
    format_seq

    validate_sequence 
    revcom 
    base_content 
    dna2peptide 
    codon2aa 
    generate_random_seqence

    shuffle_sequences 
    rename_fasta_header 
    clean_fasta_header 

=head1 SYNOPSIS

  use BioUtil::Seq;


=head1 SUBROUTINES/METHODS


=head2 FastaReader

FastaReader is a fasta file parser using closure.
FastaReader returns an anonymous subroutine, when called, it
will return a fasta record which is reference of an array
containing fasta header and sequence.

A boolean argument is optional. If set as "true", "return" ("\r") and
"new line" ("\n") symbols in sequence will not be trimed.

Example:

   # my $next_seq = FastaReader("test.fa", 1);
   my $next_seq = FastaReader("test.fa");

   while ( my $fa = &$next_seq() ) {
       my ( $header, $seq ) = @$fa;

       print ">$header\n$seq\n";
   }

=cut

sub FastaReader {
    my ( $file, $not_trim ) = @_;

    my ( $last_header, $seq_buffer ) = ( '', '' ); # buffer for header and seq
    my ( $header,      $seq )        = ( '', '' ); # current header and seq
    my $finished = 0;

    open FH, "<", $file
        or die "fail to open file: $file!\n";

    return sub {

        if ($finished) {                           # end of file
            return undef;
        }

        while (<FH>) {
            s/^\s+//;    # remove the space at the front of line

            if (/^>(.*)/) {    # header line
                ( $header, $last_header ) = ( $last_header, $1 );
                ( $seq,    $seq_buffer )  = ( $seq_buffer,  '' );

                # only output fasta records with non-blank header
                if ( $header ne '' ) {
                    $seq =~ s/\s+//g unless $not_trim;
                    return [ $header, $seq ];
                }
            }
            else {
                $seq_buffer .= $_;    # append seq
            }
        }
        close FH;
        $finished = 1;

        # last record
        # only output fasta records with non-blank header
        if ( $last_header ne '' ) {
            $seq_buffer =~ s/\s+//g unless $not_trim;
            return [ $last_header, $seq_buffer ];
        }
    };
}

=head2 read_sequence_from_fasta_file

Read all sequences from fasta file.

Example:

    my $seqs = read_sequence_from_fasta_file($file);
    for my $header (keys %$seqs) {
        my $seq = $$seqs{$header};
        print ">$header\n$seq\n";
    }

=cut

sub read_sequence_from_fasta_file {
    my ( $file, $not_trim ) = @_;
    my $seqs = {};

    my $next_seq = FastaReader( $file, $not_trim );
    while ( my $fa = &$next_seq() ) {
        my ( $header, $seq ) = @$fa;

        $$seqs{$header} = $seq;
    }

    return $seqs;
}

=head2 write_sequence_to_fasta_file

Example:

    my $seq = {"seq1" => "acgagaggag"};
    write_sequence_to_fasta_file($seq, "seq.fa");

=cut

sub write_sequence_to_fasta_file {
    my ( $seqs, $file, $n ) = @_;
    unless ( ref $seqs eq 'HASH' ) {
        warn "seqs should be reference of hash\n";
        return 0;
    }
    $n = 70 unless defined $n;

    open OUT, ">$file" or die "failed to write to $file\n";
    for ( keys %$seqs ) {
        print OUT ">$_\n", format_seq( $$seqs{$_}, $n ), "\n";
    }
    close OUT;
}

=head2 format_seq

Format sequence to readable text

Example:

    my $seq = {"seq1" => "acgagaggag"};
    write_sequence_to_fasta_file($seq, "seq.fa");

=cut

sub format_seq {
    my ( $s, $n ) = @_;
    $n = 70 unless defined $n;
    unless ( $n =~ /^\d+$/ and $n > 0 ) {
        warn "n should be positive integer\n";
        return $s;
    }

    my $s2 = '';
    my ( $j, $int );
    $int = int( ( length $s ) / $n );
    for ( $j = 0; $j <= $int; $j++ ) {
        $s2 .= substr( $s, $j * $n, $n ) . "\n";
    }
    return $s2;
}

=head2 validate_sequence

Validate a sequence.

Legale symbols:

    DNA: ACGTRYSWKMBDHV
    RNA: ACGURYSWKMBDHV
    Protein: ACDEFGHIKLMNPQRSTVWY
    gap and space: - *.

Example:

    if (validate_sequence($seq)) {
        # do some thing
    }

=cut

sub validate_sequence {
    my ($seq) = @_;
    return 0 if $seq =~ /[^\.\-\s_*ABCDEFGHIKLMNPQRSTUVWY]/i;
    return 1;
}

=head2 revcom

Reverse complement sequence

my $recom = revcom($seq);

=cut

sub revcom {
    my ($s) = @_;
    $s =~ tr/ACGTRYMKSWBDHVNacgtrymkswbdhvn/TGCAYRKMWSVHDBNtgcayrkmwsvhdbn/;
    return reverse $s;
}

=head2 base_content

Example:

    my $gc_cotent = base_content('gc', $seq);

=cut

sub base_content {
    my ( $bases, $seq ) = @_;
    if ( $seq eq '' ) {
        return 0;
    }

    my $sum = 0;
    $sum += $seq =~ s/$_/$_/ig for split "", $bases;
    return sprintf "%.4f", $sum / length $seq;
}

=head2 dna2peptide

Translate DNA sequence into a peptide

=cut

sub dna2peptide {
    my ($dna) = @_;
    my $protein = '';

   # Translate each three-base codon to an amino acid, and append to a protein
    for ( my $i = 0; $i < ( length($dna) - 2 ); $i += 3 ) {
        $protein .= codon2aa( substr( $dna, $i, 3 ) );
    }
    return $protein;
}

=head2 dna2peptide

Translate a DNA 3-character codon to an amino acid

=cut

sub codon2aa {
    my ($codon) = @_;
    $codon = uc $codon;
    my %genetic_code = (
        'TCA' => 'S',    # Serine
        'TCC' => 'S',    # Serine
        'TCG' => 'S',    # Serine
        'TCT' => 'S',    # Serine
        'TTC' => 'F',    # Phenylalanine
        'TTT' => 'F',    # Phenylalanine
        'TTA' => 'L',    # Leucine
        'TTG' => 'L',    # Leucine
        'TAC' => 'Y',    # Tyrosine
        'TAT' => 'Y',    # Tyrosine
        'TAA' => '_',    # Stop
        'TAG' => '_',    # Stop
        'TGC' => 'C',    # Cysteine
        'TGT' => 'C',    # Cysteine
        'TGA' => '_',    # Stop
        'TGG' => 'W',    # Tryptophan
        'CTA' => 'L',    # Leucine
        'CTC' => 'L',    # Leucine
        'CTG' => 'L',    # Leucine
        'CTT' => 'L',    # Leucine
        'CCA' => 'P',    # Proline
        'CCC' => 'P',    # Proline
        'CCG' => 'P',    # Proline
        'CCT' => 'P',    # Proline
        'CAC' => 'H',    # Histidine
        'CAT' => 'H',    # Histidine
        'CAA' => 'Q',    # Glutamine
        'CAG' => 'Q',    # Glutamine
        'CGA' => 'R',    # Arginine
        'CGC' => 'R',    # Arginine
        'CGG' => 'R',    # Arginine
        'CGT' => 'R',    # Arginine
        'ATA' => 'I',    # Isoleucine
        'ATC' => 'I',    # Isoleucine
        'ATT' => 'I',    # Isoleucine
        'ATG' => 'M',    # Methionine
        'ACA' => 'T',    # Threonine
        'ACC' => 'T',    # Threonine
        'ACG' => 'T',    # Threonine
        'ACT' => 'T',    # Threonine
        'AAC' => 'N',    # Asparagine
        'AAT' => 'N',    # Asparagine
        'AAA' => 'K',    # Lysine
        'AAG' => 'K',    # Lysine
        'AGC' => 'S',    # Serine
        'AGT' => 'S',    # Serine
        'AGA' => 'R',    # Arginine
        'AGG' => 'R',    # Arginine
        'GTA' => 'V',    # Valine
        'GTC' => 'V',    # Valine
        'GTG' => 'V',    # Valine
        'GTT' => 'V',    # Valine
        'GCA' => 'A',    # Alanine
        'GCC' => 'A',    # Alanine
        'GCG' => 'A',    # Alanine
        'GCT' => 'A',    # Alanine
        'GAC' => 'D',    # Aspartic Acid
        'GAT' => 'D',    # Aspartic Acid
        'GAA' => 'E',    # Glutamic Acid
        'GAG' => 'E',    # Glutamic Acid
        'GGA' => 'G',    # Glycine
        'GGC' => 'G',    # Glycine
        'GGG' => 'G',    # Glycine
        'GGT' => 'G',    # Glycine
    );

    if ( exists $genetic_code{$codon} ) {
        return $genetic_code{$codon};
    }
    else {
        print STDERR "Bad codon \"$codon\"!!\n";
        exit;
    }
}

=head2 generate_random_seqence

Example:

    my @alphabet = qw/a c g t/;
    my $seq = generate_random_seqence( \@alphabet, 50 );

=cut

sub generate_random_seqence {
    my ( $alphabet, $length ) = @_;
    unless ( ref $alphabet eq 'ARRAY' ) {
        warn "alphabet should be ref of array\n";
        return 0;
    }

    my $n = @$alphabet;
    my $seq;
    $seq .= $$alphabet[ int rand($n) ] for ( 1 .. $length );
    return $seq;
}

=head2 shuffle sequences

Example:

    shuffle_sequences($file, "$file.shuf.fa");

=cut

sub shuffle_sequences {
    my ( $file, $file_out, $not_trim ) = @_;
    my $seqs = read_sequence_from_fasta_file( $file, $not_trim );
    my @keys = shuffle( keys %$seqs );

    $file_out = "$file.shuffled.fa" unless defined $file_out;
    open OUT, ">$file_out" or die "fail to write file $file_out\n";
    print OUT ">$_\n$$seqs{$_}\n" for @keys;
    close OUT;

    return $file_out;
}

=head2 rename_fasta_header

Rename fasta header with regexp.

Example:
    
    # delete some symbols
    my $n = rename_fasta_header('[^a-z\d\s\-\_\(\)\[\]\|]', '', $file, "$file.rename.fa");
    print "$n records renamed\n";

=cut

sub rename_fasta_header {
    my ( $regex, $repalcement, $file, $outfile ) = @_;

    open IN,  "<", $file    or die "fail to open file: $file\n";
    open OUT, ">", $outfile or die "fail to wirte file: $outfile\n";

    my $head = '';
    my $n    = 0;
    while (<IN>) {
        if (/^\s*>(.*)\r?\n/) {
            $head = $1;
            if ( $head =~ /$regex/ ) {
                $head =~ s/$regex/$repalcement/g;
                $n++;
            }
            print OUT ">$head\n";
        }
        else {
            print OUT $_;
        }
    }
    close IN;
    close OUT;

    return $n;
}

=head2 clean_fasta_header

Rename given symbols to repalcement string. 
Because, some symbols in fasta header will cause unexpected result.

Example:

    my  $file = "test.fa";
    my $n = clean_fasta_header($file, "$file.rename.fa");
    # replace any symbol in (\/:*?"<>|) with '', i.e. deleting.
    # my $n = clean_fasta_header($file, "$file.rename.fa", '',  '\/:*?"<>|');
    print "$n records renamed\n";

=cut

sub clean_fasta_header {
    my ( $file, $outfile, $replacement, $symbols ) = @_;
    $replacement = "_" unless defined $replacement;

    my @default = split //, '\/:*?"<>|';
    $symbols = \@default unless defined $symbols;
    unless ( ref $symbols eq 'ARRAY' ) {
        warn "symbols should be ref of array\n";
        return 0;
    }
    my $re = join '', map { quotemeta $_ } @$symbols;
    open IN,  "<", $file    or die "fail to open file: $file\n";
    open OUT, ">", $outfile or die "fail to wirte file: $outfile\n";

    my $head = '';
    my $n    = 0;
    while (<IN>) {
        if (/^\s*>(.*)\r?\n/) {
            $head = $1;
            if ( $head =~ /[$re]/ ) {
                $head =~ s/[$re]/$replacement/g;
                $n++;
            }
            print OUT ">$head\n";
        }
        else {
            print OUT $_;
        }
    }
    close IN;
    close OUT;

    return $n;
}

1;
