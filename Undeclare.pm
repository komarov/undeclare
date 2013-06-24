package Undeclare;

use base 'Exporter';
our @EXPORT    = ();
our @EXPORT_OK = qw( undeclare undeclareFile );

use strict;
use warnings;
use Carp;

use PPI;
use PPI::Find;
use List::Util qw( max );
use Parse::Method::Signatures;
use Cwd;


#-------------------------------------------------------------------------------
sub undeclareFile {
   my ( $InputFileName, $OutputFileName ) = @_;
   $OutputFileName ||= $InputFileName;

   open my $InputFile, '<', $InputFileName 
      or die "Could not open input file $InputFileName, cwd: " . getcwd();
   my $Input = join( '', <$InputFile> );
   close $InputFile;
   open my $OutputFile, '>', $OutputFileName 
      or die "Could not open output file $OutputFileName, cwd: " . getcwd();
   print { $OutputFile } undeclare( $Input );
   close $OutputFile;
   return 1;
}


#-------------------------------------------------------------------------------
sub undeclare {
   my $Input = shift;

   my $Doc = PPI::Document->new( \$Input );

   my $MethodTokens = $Doc->find( 
      sub { 
         return $_[ 1 ]->isa( 'PPI::Token::Word' ) && $_[ 1 ]->content eq 'method' 
      } 
   );

   if( ref( $MethodTokens ) ne 'ARRAY' ) {
   # Have nothing to do here
      return $Input;
   }

   foreach my $MethodToken ( @$MethodTokens ) {
      _undeclareMethod( $MethodToken );
   }
   return $Doc->serialize();
}


#-------------------------------------------------------------------------------
sub _undeclareMethod {
   my $MethodToken = shift;

   $MethodToken->set_content( 'sub' );

   my ( $CodeBlock, $SignatureToken ) = _findParts( $MethodToken );

   my $InsertBlock = "\n";
   if( $SignatureToken ) {
      $InsertBlock .= _processSignature( $SignatureToken );
      $SignatureToken->remove(); 
   }
   else {
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
   # indent generated code by found indent level
      $InsertBlock = _prefix( $InsertBlock, $FoundIndent );
   }
   $CodeBlock->first_token()->add_content( $InsertBlock );

   return;
}


#-------------------------------------------------------------------------------
sub _findParts {
   my $MethodToken = shift;

   my ( $CodeBlock, $SignatureToken ) = ();
   my $MethodName = $MethodToken->snext_sibling();
   my $Sibling;
   if ( $MethodName =~ /^\{/ ){
     $Sibling = $MethodName;
   }else{
     $Sibling = $MethodName->snext_sibling() // undef;
   }

   if ( defined $Sibling ){
     while( $Sibling && ! $Sibling->isa( 'PPI::Structure::Block' ) ) {
        # Such block is an actual code block
       
           if( $Sibling->isa( 'PPI::Structure::List' ) ) {
              $SignatureToken = $Sibling;
           }
           $Sibling = $Sibling->snext_sibling();
     }
   }
   $CodeBlock = $Sibling;

   return ( $CodeBlock, $SignatureToken );
}


#-------------------------------------------------------------------------------
sub _prefix {
   my ( $Block, $Prefix ) = @_;
   my @Lines = split /(\n)/, $Block;
   return join( '', map { $_ eq "\n" ? $_ : $Prefix . $_ } @Lines );
}


#-------------------------------------------------------------------------------
sub _processSignature {
   my $SignatureToken = shift;

   my $Signature = Parse::Method::Signatures->signature( $SignatureToken->content() );
   my @Lexicals  = ();
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

   my $DefaultValuesBlock = '';
   foreach my $VariableName ( keys %DefaultValues ) {
      $DefaultValuesBlock .= "$VariableName = $DefaultValues{ $VariableName } if !defined $VariableName;\n"; 
      # //= operator is not always available
      # otherwise it would be 
      # $DefaultValuesBlock .= "$VariableName //= $DefaultValues{ $VariableName };\n"; 
   }
   $DefaultValuesBlock = "# Default values\n$DefaultValuesBlock" if $DefaultValuesBlock;

   my $Vars = join q{,}, @Lexicals;
   return "my (${Vars}) = \@_;\n" . $NamedParametersBlock . $DefaultValuesBlock;
}

1;
__END__
=pod

=head1 NAME

Undeclare

=head1 DESCRIPTION

A simple tool for translating MooseX::Method::Signatures syntax sugar
into native subs and parameters parsing

Motivation: http://www.mail-archive.com/moose@perl.org/msg01220.html

=head1 FUNCTIONS

=head2 undeclare( $InputString )

Takes one argument, returns the result of undeclaring.

=head2 undeclareFile( $InputFileName, [ $OutputFileName ] )

Reads content of $InputFileName and writes the result to $OutputFileName.

Rewrites file in-place if only one argument is provided.

=head1 AUTHORS AND CONTRIBUTORS

Oleg Komarov, Vladimir Kim

=head1 LICENSE

This module is free software and is released under the same terms as Perl itself.
THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, 
BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY 
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
POSSIBILITY OF SUCH DAMAGE.

=head1 SEE ALSO
L<MooseX::Declare>, L<MooseX::Method::Signatures>, L<Moose>

=cut
