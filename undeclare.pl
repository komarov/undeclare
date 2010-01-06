#!/usr/bin/perl

# A simple tool for translating MooseX::Method::Signatures syntax sugar
# into native subs and parameters parsing
# Motivation: http://www.mail-archive.com/moose@perl.org/msg01220.html
#
# Authors and contributors: Komarov Oleg, Kim Vladimir
# Last update: 2010-01-06

use strict;
use warnings;

use PPI;
use PPI::Find;
use List::Util qw( max );

my $Input = join( '', <> );
my $Doc = PPI::Document->new( \$Input );

my $Methods = $Doc->find( sub { return $_[ 1 ]->isa( 'PPI::Token::Word' ) && $_[ 1 ]->content eq 'method' } );
if( ref( $Methods ) eq 'ARRAY' ) {
   foreach my $Method ( @$Methods ) {
      $Method->set_content( 'sub' );
      my $AfterMethodName = $Method->snext_sibling()->snext_sibling();
      my $CodeBlock;
      my $InsertBlock = "\n";
      if( $AfterMethodName->isa( 'PPI::Structure::List' ) ) {
      # method has a signature
         $CodeBlock = $AfterMethodName->snext_sibling();
         my $Signature = $AfterMethodName->remove()->content();
         $Signature =~ s/^\(//;
         $Signature =~ s/\)$//;
         if( $Signature =~ s{^\s*\w*\s* (\$\w+): }{}xms ) {
         # explicit method invocant is specified
            $InsertBlock .= "my $1 = shift;\n";
         }
         else {
            $InsertBlock .= "my \$self = shift;\n";
         }
         my $ParametersAreNamed = ( $Signature =~ /:\$/ );
         if( $ParametersAreNamed ) {
            $InsertBlock .= parseNamedParameters( $Signature );
         }
         else {
            $InsertBlock .= parsePositionedParameters( $Signature );
         }
      }
      elsif( $AfterMethodName->isa( 'PPI::Structure::Block' ) ) {
      # method doesn't have a signature
         $CodeBlock = $AfterMethodName;
         $InsertBlock .= 'my $self = shift;' . "\n";
      }

      # try to find whitespace inside the method to indent our generated code
      my $FindIndent = PPI::Find->new(
         sub {
            return $_[ 0 ]->isa( 'PPI::Token::Whitespace' ) && $_[ 0 ] ne "\n";
         }
      );
      $FindIndent->start( $CodeBlock );
      if( my $FoundIndent = $FindIndent->match() ) {
         $InsertBlock = prefix( $InsertBlock, $FoundIndent );
      }

      $CodeBlock->first_token()->add_content( $InsertBlock );
   }
}
print $Doc->serialize();


#-------------------------------------------------------------------------------
sub parsePositionedParameters {
   my $ArgStr = shift;

   my @ParsedArgs;
   foreach my $Arg ( split /,/, $ArgStr ) {
      $Arg =~ s{.*?(\$\w+).*}{$1};
      push @ParsedArgs, $Arg;
   }

   return 'my ( ' . join( ', ', @ParsedArgs ) . ' ) = @_;' . "\n";
}


#-------------------------------------------------------------------------------
sub parseNamedParameters {
   my $ArgStr = shift;

   my $Output = "my \%__params = \@_;\n";
   my @ArgNames = split /,/, $ArgStr;
   foreach my $ArgName ( @ArgNames ) {
      $ArgName =~ s{.*?\$(\w+).*}{$1};
   }
   my $MaxNameLength = max( map { length( $_ ) } @ArgNames );
   foreach my $ArgName ( @ArgNames ) {
      my $AlignIndent = $MaxNameLength - length( $ArgName );
      $Output .= "my \$$ArgName" . ( ' ' x $AlignIndent ) . " = \$__params{ '$ArgName' };\n";
   }

   return $Output;
}


#-------------------------------------------------------------------------------
sub prefix {
   my ( $Block, $Prefix ) = @_;
   my @Lines = split /(\n)/, $Block;
   return join( '', map { $_ eq "\n" ? $_ : $Prefix . $_ } @Lines );
}
