# Copyright (C) 2007-2010, Parrot Foundation.
# $Id$

=head1 NAME

Parrot::Pmc2c::PMC::default

=head1 DESCRIPTION

Instance Methods

=head1 METHODS

=over 4

=cut

package Parrot::Pmc2c::PMC::default;
use strict;
use warnings;
use Parrot::Pmc2c::UtilFunctions qw( return_statement );
use base qw( Parrot::Pmc2c::PMC );

=item C<pre_method_gen()>

Always true.

=back

=cut

sub pre_method_gen {
    my ($self) = @_;

    # vtables
    foreach my $method ( @{ $self->vtable->methods } ) {
        my $vt_method_name = $method->name;
        next unless $self->unimplemented_vtable($vt_method_name);
        $self->add_method($self->_generate_default_method($self, $method, 'cant_do_method'));
    }
    return 1;
}

sub gen_methods {
    my ($self) = @_;

    $self->SUPER::gen_methods;

    # Generate RO variants.
    my $ro = Parrot::Pmc2c::PMC::RO->new($self);
    $ro->{emitter} = $self->{emitter};
    foreach my $method ( @{ $self->vtable->methods } ) {
        my $vt_method_name = $method->name;
        if ( $self->vtable_method_does_write($vt_method_name) ) {
            my $m = $self->_generate_default_method($ro, $method, 'cant_do_write_method');
            $m->generate_body($ro);
        }
    }
}

sub _generate_default_method {
    my ($self, $pmc, $method, $stub_func) = @_;

    my $clone = $method->clone(
         {
             parent_name => $self->name,
             type        => Parrot::Pmc2c::Method::VTABLE,
         }
     );

    # take care to mark the parameters as unused
    # to avoid compiler warnings
    my $body;
    foreach my $param (split /,\s*/, $method->parameters) {
        $param =~ s/.*\b(\w+)/$1/;
        $body .= "    UNUSED($param)\n";
    }
    my $vt_method_name = uc $method->name;
    $body .= qq{    $stub_func(interp, _self, PARROT_VTABLE_SLOT_$vt_method_name);\n};

    $clone->body( Parrot::Pmc2c::Emitter->text($body));

    $clone;
}

sub update_vtable_func {
    "";
}

# Really build default vtable.
sub get_vtable_func {
    my ($self) = @_;

    my $cout = "";

    my $vtable_decl = $self->vtable_decl("temp_vtable", 'enum_class_default');

    $cout .= <<"EOC";

PARROT_EXPORT VTABLE* Parrot_default_get_vtable(PARROT_INTERP) {

    static const char attr_defs [] = "";

$vtable_decl

    return Parrot_clone_vtable(interp, &temp_vtable);
}

EOC

    # Generate RO version of default VTABLE.
    my $ro_vtable_decl = '';
    foreach my $name ( @{ $self->vtable->names } ) {
        if ($self->vtable_method_does_write($name)) {
            $ro_vtable_decl .= "    vt->$name = Parrot_default_ro_${name};\n";
        }
    }

    $cout .= <<"EOC";

PARROT_EXPORT VTABLE* Parrot_default_ro_get_vtable(PARROT_INTERP) {

    VTABLE * const vt = Parrot_default_get_vtable(interp);

$ro_vtable_decl

    return vt;
}

EOC

    # Generate WB version of default VTABLE.
    $ro_vtable_decl = '';
    foreach my $name ( @{ $self->vtable->names } ) {
        if ($self->vtable_method_does_write($name)) {
            $ro_vtable_decl .= "    vt->$name = Parrot_default_wb_${name};\n";
        }
    }

    $cout .= <<"EOC";

PARROT_EXPORT VTABLE* Parrot_default_wb_get_vtable(PARROT_INTERP) {

    VTABLE * const vt = Parrot_default_get_vtable(interp);

$ro_vtable_decl

    return vt;
}

EOC

    # Generate WB vtable for implemented non-updating methods
    my $vtable_updates = '';
    foreach my $name ( @{ $self->vtable->names} ) {
        next unless exists $self->{has_method}{$name}
                    && $self->vtable_method_does_write($name);
        next if $name =~ m{ ^init }xo;
        $vtable_updates .= "    vt->$name = Parrot_default_wb_${name};\n";
    }

    $cout .= <<"EOC";

PARROT_EXPORT
VTABLE *Parrot_default_wb_update_vtable(ARGMOD(VTABLE *vt)) {
$vtable_updates
    return vt;
}

EOC
    $cout;
}

1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
