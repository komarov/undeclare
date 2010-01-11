#!/usr/bin/perl

# A simple tool for translating MooseX::Method::Signatures syntax sugar
# into native subs and parameters parsing
# Motivation: http://www.mail-archive.com/moose@perl.org/msg01220.html
#
# Authors and contributors: Komarov Oleg, Kim Vladimir
# Last update: 2010-01-11

use strict;
use warnings;

use PPI;
use PPI::Find;
use List::Util qw( max );
use Parse::Method::Signatures;

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

         my $SignatureToken = $AfterMethodName->remove();
         my $Signature      = Parse::Method::Signatures->signature( $SignatureToken->content() );
         my @Lexicals = ();
         push @Lexicals, $Signature->has_invocant ? $Signature->invocant->variable_name : '$self';

         my %DefaultValues = ();
         if( $Signature->has_positional_params ) {
            push @Lexicals, map { $_->variable_name } $Signature->positional_params;
            foreach my $Param ( grep { $_->has_default_value } $Signature->positional_params ) {
               $DefaultValues{ $Param->variable_name } = $Param->default_value;
            }
         }
         my $NamedParametersBlock = '';
         if( $Signature->has_named_params ) {
            my $MaxVariableNameLength = max( map { length( $_->variable_name ) } $Signature->named_params );
            push @Lexicals, '%__named_params';
            $NamedParametersBlock = join( 
               '', 
               map { 
                  "my " . $_->variable_name . ( ' ' x ( $MaxVariableNameLength - length( $_->variable_name ) ) ) 
                  . " = \$__named_params{ '" . $_->label . "' };\n" 
               } $Signature->named_params 
            );
            foreach my $Param ( grep { $_->has_default_value } $Signature->named_params ) {
               $DefaultValues{ $Param->variable_name } = $Param->default_value;
            }
         }

         my $Vars = join q{,}, @Lexicals;
         $InsertBlock .= "my (${Vars}) = \@_;\n";

         my $DefaultValuesBlock = '';
         foreach my $VariableName ( keys %DefaultValues ) {
            $DefaultValuesBlock .= "$VariableName = $DefaultValues{ $VariableName } if !defined $VariableName;\n"; 
            # //= operator is not always available
            # otherwise it would be 
            # $DefaultValuesBlock .= "$VariableName //= $DefaultValues{ $VariableName };\n"; 
         }
         $DefaultValuesBlock = "# Default values\n$DefaultValuesBlock" if $DefaultValuesBlock;

         $InsertBlock .= $NamedParametersBlock;        
         $InsertBlock .= $DefaultValuesBlock;

      }
      elsif( $AfterMethodName->isa( 'PPI::Structure::Block' ) ) {
      # method doesn't have a signature
         $CodeBlock = $AfterMethodName;
         $InsertBlock .= "my \$self = shift;\n";
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
exit;


#-------------------------------------------------------------------------------
sub prefix {
   my ( $Block, $Prefix ) = @_;
   my @Lines = split /(\n)/, $Block;
   return join( '', map { $_ eq "\n" ? $_ : $Prefix . $_ } @Lines );
}
