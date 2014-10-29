package BioUtil::Util;

use File::Path qw/remove_tree/;

require Exporter;
@ISA    = (Exporter);
@EXPORT = qw(
    get_file_list

    extract_parameters_from_string
    get_parameters_from_file

    get_list_from_file
    get_column_data

    read_json_file
    write_json_file

    run

    check_positive_integer
    
    filename_prefix
    check_all_files_exist
    check_in_out_dir 
    rm_and_mkdir
);

use vars qw($VERSION);

use 5.010_000;
use strict;
use warnings FATAL => 'all';

use Encode qw/ encode_utf8 /;
use File::Path qw(make_path remove_tree);
use File::Find;
use File::Basename;
use JSON;

=head1 NAME

BioUtil::Util - Utilities for operation on data or file

Some great modules like BioPerl provide many robust solutions. 
However, it is not easy to install for someone in some platforms.
And for some simple task scripts, a lite module may be a good choice.
So I reinvented some wheels and added some useful utilities into this module,
hoping it would be helpful.

=head1 VERSION

Version 2014.0927

=cut

our $VERSION = 2014.0927;

=head1 EXPORT

    get_file_list

    extract_parameters_from_string
    get_parameters_from_file

    get_list_from_file
    get_column_data

    read_json_file
    write_json_file

    run

    check_positive_integer
    
    filename_prefix
    check_all_files_exist
    check_in_out_dir 
    rm_and_mkdir

=head1 SYNOPSIS

  use BioUtil::Util;


=head1 SUBROUTINES/METHODS

=head2 get_file_list

Find files/directories with custom filter, 
max serach depth could be specified.

Example (searching perl scripts)

    my $dir   = "~";
    my $depth = 2;

    my $list = get_file_list(
        $dir,
        sub {
            if ( -d or /^\./i ) {  # ignore configuration file and folders
                return 0;
            }
            if (/\.pm/i or /\.pl/i) {
                return 1;
            }
            return 0;
        },
        $depth
    );
    print "$_\n" for @$list;

=cut

sub get_file_list {

    # filter is a subroutine to filter a file
    my ( $dir, $filter, $depth ) = @_;
    $dir =~ s/\/+/\//g;
    $dir =~ s/\/$//;

    $depth = 1 << 30 unless defined $depth;
    unless ( $depth =~ /^\d+$/ and $depth > 0 ) {
        warn "depth should be positive integer\n";
        return [];
    }
    # print "$dir\n";
    my $depth0 = $dir =~ tr/\//\//;

    my $files  = [];
    my $wanted = sub {
        return if /^\.+$/;
        return if $_ eq $dir;

        # check depth
        return if $File::Find::name =~ tr/\//\// - $depth0 > $depth;

        if ( &$filter($_) ) {
            push @$files, $File::Find::name;
        }
    };

    find( $wanted, ($dir) );

    return $files;
}

=head2 extract_parameters_from_string

Extract parameters from string.

The regular expression is 
    
    /([\w\d\_\-\.]+)\s*=\s*([^\=;]*)[\s;]*/

Example:

    # bad format, but could also be parsed
    # my $s = " s = b; a=test; b_c=12 3; a.b =; b
    # = asdf
    # sd; ads-f = 12313";

    # recommended
    my $s = "key1=abcde; key2=123; conf.a=file; conf.b=12; ";

    my $pa = extract_parameters_from_string($s);
    print "=$_:$$p{$_}=\n" for sort keys %$pa;

=cut

sub extract_parameters_from_string {
    my ($s) = @_;
    my $parameters = {};
    while ( $s =~ /([\w\d\_\-\.]+)\s*=\s*([^\=;]*)[\s;]*/gm ) {
        warn "$1 was defined more than once\n" if defined $$parameters{$1};
        $$parameters{$1} = $2;
    }
    return $parameters;
}

=head2 get_parameters_from_file

Get parameters from a file.
Comments start with # are allowed in file.

Example:
    
    my $pa = get_parameters_from_file("d.txt");
    print "$_: $$pa{$_}\n" for sort keys %$pa;

For a file with content:

    # cell phone 
    apple = 1 # note

    nokia = 2 #

output is:
    
    apple: 1
    nokia: 2

=cut

sub get_parameters_from_file {
    my ($file) = @_;
    my $parameters = {};
    open IN, $file or die "fail to open file $file\n";
    while (<IN>) {
        s/^\s+|\s+$//g;
        next if $_ eq ''    # blank line
            or /^#/;        # annotation
        s/#.*//g;           # delete annotation

        next unless /([\w\d\_\-\.]+)\s*=\s*(.+)/;
        $$parameters{$1} = $2;
    }
    close IN;
    return $parameters;
}

=head2 get_list_from_file

Get list from a file.
Comments start with # are allowed in file.

Example:
    
    my $list = get_list_from_file("d.txt");
    print "$_\n" for @$list;

For a file with content:

    # cell phone 
    apple # note

    nokia

output is:
    
    apple
    nokia

=cut

sub get_list_from_file {
    my ($file) = @_;
    open IN, "<", $file or die "fail to open file $file\n";
    my @list = ();
    while (<IN>) {
        s/\r?\n//g;
        s/^\s+|\s+$//g;
        next if $_ eq ''    # blank line
            or /^#/;        # annotation
        s/#.*//g;           # delete annotation

        push @list, $_;
    }
    close IN;
    return \@list;
}

=head2 get_column_data

Get one column of a file.

Example:

    my $list = get_column_data("d.txt", 2);
    print "$_\n" for @$list;

=cut

sub get_column_data {
    my ( $file, $column ) = @_;
    unless ( $column =~ /^(\d+)$/ and $column > 0 ) {
        warn "column number ($column) should be positive integer\n";
        $column = 1;
    }

    open IN, "<", $file or die "failed to open file: $file\n";
    my @linedata = ();
    my @data     = ();
    my $n        = 0;
    while (<IN>) {
        s/\r?\n//;
        @linedata = split /\t/, $_;
        $n = scalar @linedata;
        next unless $n > 0;

        if ( $column > $n ) {
            die
                "number of columns of this line ($n) is less than given column number ($column)\n";
        }

        push @data, $linedata[ $column - 1 ];
    }
    close IN;

    return \@data;
}

=head2 read_json_file

Read json file and decode it into a hash ref.

Example:

    my $hashref = read_json_file($file);

=cut

sub read_json_file {
    my ($file) = @_;
    open IN, "<:encoding(utf8)", $file
        or die "fail to open json file: $file\n";
    my $text;
    while (<IN>) {
        s/\s*#+.*\r?\n?//g;    # remove annotation
        $text .= $1 if / *(.+)/;
    }
    close IN;
    my $hash = decode_json($text);
    return $hash;
}

=head2 write_json_file

Write a hash ref into a file.

Example:
    
    my $hashref = { "a" => 1, "b" => 2 };
    write_json_file($hashref, $file);

=cut

sub write_json_file {
    my ( $hash, $file ) = @_;
    my $json = JSON->new->allow_nonref;
    my $text = $json->pretty->encode($hash);
    $text = encode_utf8( $text );
    open OUT, ">:encoding(utf8)", $file
        or die "fail to open json file: $file\n";
    print OUT $text;
    close OUT;
}

=head2 run

Run a command

Example:
    
    run('date');

=cut

sub run {
    my ($cmd) = @_;
    system($cmd);

    if ( $? == -1 ) {
        die "[ERROR] fail to run: $cmd. Command ("
            . ( split /\s+/, $cmd )[0]
            . ") not found\n";
    }
    elsif ( $? & 127 ) {
        printf "[ERROR] command died with signal %d, %s coredump\n",
            ( $? & 127 ), ( $? & 128 ) ? 'with' : 'without';
    }
    else {
        # 0, ok
    }
}

=head2 check_positive_integer

Check Positive Integer

Example:
    
    rcheck_positive_integer(1);

=cut

sub check_positive_integer {
    my ($n) = @_;
    die "positive integer needed ($n given)"
        unless $n =~ /^\d+$/ and $n != 0;
}

=head2 check_positive_integer

Get filename prefix

Example:
    
    filename_prefix("test.fa"); # "test"
    filename_prefix("tmp");     # "tmp"

=cut
sub filename_prefix {
    my ($file) = @_;
    if ( $file =~ /(.+)\..+?$/ ) {
        return $1;
    }
    else {
        return $file;
    }
}


=head2 check_all_files_exist

    Check whether all files existed.

=cut
sub check_all_files_exist {
    my $flag = 1;
    for (@_) {
        if ( not -e $_) {
            return 0;
        }
    }
    return 1;
}

=head2 check_in_out_dir

    Check in and out directory.

Example:
    
    check_in_out_dir("~/dir", "~/dir.out");

=cut

sub check_in_out_dir {
    my ( $in, $out ) = @_;
    die "dir $in not found."
        unless -e $in;

    die "$in is not a directory.\n"
        unless -d $in;

    $in =~ s/\/$//;
    $out =~ s/\/$//;
    die "out dir shoud be different from in dir!\n"
        if $in eq $out;
}


=head2 rm_and_mkdir

    Make a directory, remove it firstly if it exists.

Example:
    
    rm_and_mkdir("out")

=cut


sub rm_and_mkdir {
    my ($dir) = @_;
    if ( -e $dir ) {
        remove_tree($dir) or die "fail to remove: $dir\n";
    }
    mkdir $dir or die "fail to mkdir: $dir\n";
}

1;
