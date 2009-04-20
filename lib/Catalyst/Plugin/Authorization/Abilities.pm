#!/usr/bin/perl

package Catalyst::Plugin::Authorization::Abilities;

use strict;
use warnings;

use Scalar::Util        ();
use Catalyst::Exception ();

our $VERSION = '0.01';

sub check_user_ability {
	my ($c, @actions) = @_;

	local $@;
	eval { $c->assert_user_ability(@actions) };
}

sub assert_user_ability {
	my ($c, @actions) = @_;

	my $user;

	if (Scalar::Util::blessed($actions[0]) && $actions[0]->isa("Catalyst::Authentication::User")) {
		# A user was supplied in the arguments
		$user = shift @actions;
	}

	$user ||= $c->user;

	Catalyst::Exception->throw("No logged in user, and none supplied as argument") unless $user;

	my $super_user_id = $c->config->{'abilities'}->{'super_user_id'} || 1;
	if ($user->id == $super_user_id) {
		# The super-user can do anything he wants
		$c->log->debug("Ability granted: @actions") if $c->debug;
		return 1;
	}

	my $gflag; # Global flag for all actions
	foreach (@actions) {
		my $lflag; # Local flag for one action
		foreach my $act ($user->actions) {
			# Check specific user abilities
			if ($act->name eq $_) {
				$lflag = 1;
			}
		}
		unless ($lflag) {
			# Check user abilities via roles
			foreach my $role ($user->user_roles) {
				foreach my $act ($role->actions) {
					if ($act->name eq $_) {
						$lflag = 1;
					}
				}
			}
		}

		if ($lflag) {
			# Action granted, set gflag to 1 temporarily
			$gflag = 1;
		} else {
			# Action not granted, undef gflag and exit loop
			undef $gflag;
			last;
		}
	}

	local $" = ", ";
	if ($gflag) {
		$c->log->debug("Ability granted: @actions") if $c->debug;
		return 1;
	} else {
		$c->log->debug("Ability denied: @actions") if $c->debug;
		Catalyst::Exception->throw("Missing abilities");
	}
}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Authorization::Abilities - Ability based authorization for Catalyst based on Catalyst::Plugin::Authentication and Catalyst::Plugin::Authorization::Roles

=head1 SYNOPSIS

	# In MyApp.pm (notice we do not use Authorization::Roles):

	use Catalyst qw/
		Authentication
		Authorization::Abilities
	/;
	__PACKAGE__->config->{'abilities'}->{'super_user_id'} = 1;

	# Anywhere in your code

	sub delete : Local {
		my ( $self, $c ) = @_;

		$c->assert_user_ability( qw/delete_foo/ ); # check if the user can perform a certain action, such as delete_foo
		$c->model("Foo")->delete_all();
	}

	# Checkout required database schemas under REQUIRED SCHEMAS

=head1 DESCRIPTION

Ability based access control is an extension of the role based access control
available through L<Catalyst::Plugin::Authorization::Roles>. In this plugin, however,
every user has a list of actions he is allowed to perform, and every restricted
part of the application makes an assertion about the necessary abilities.

Abilities to perform certain actions can be given to a user specifically, or
via roles the user can assume. For example, if user 'user01' is member of role
'admin', and this user wishes to perform some action, for example 'delete_foo',
than they will only be able to do so if the 'delete_foo' ability was given to
either the user itself or the 'admin' role itself.

With C<check_user_ability> and C<assert_user_ability>, these conditionals are checked
to grant or deny the user access to the required action.

This method of authorization allows for much more flexibility with regards to
access control, such that roles and abilities can be added/edited/deleted using
the application itself (via your own controllers!). This is useful for applications
such as message boards, where the administrator might wish to create roles with
certain actions and associate users with those roles. For example, the admin can
create an 'editor' role, giving users of this role the ability to edit and delete
posts, but not any other administrative action. So in essence, this plugin takes
the control of who's able to do what from the developer and hands it to the end-user.

Note that this plugin is not to be used in conjunction with L<Catalyst::Plugin::Authorization::Roles>,
and that it requires several tables to be present in the database/schema (see SYNOPSIS).

=head1 METHODS

=over 4

=item assert_user_ability [ $user ], @actions

Checks that the user (as supplied by the first argument, or, if omitted,
C<< $c->user >>) has the ability to perform specified actions.

If for any reason (C<< $c->user >> is not defined, the user is missing the
appropriate action/role, etc.) the check fails, an error is thrown.

You can either catch these errors with an eval, or clean them up in your C<end>
action.

The action automatically grants ability, no matter which actions were passed,
to the super-user. This is probably the user who installed MyApp and is setting
it up, so that he can create roles and assign actions (otherwise the installing
user might have never been able to do anything). The super-user is identified
by supplying a user ID to MyApp's config (see SYNOPSIS). This setting defaults
to user ID 1.

=item check_user_ability [ $user ], @roles

Takes the same args as C<assert_user_ability>, and performs the same check, but
instead of throwing errors returns a boolean value.

=back

=head1 REQUIRED SCHEMAS
MyApp::Schema::Actions

	package MyApp::Schema::Actions;

	...

	__PACKAGE__->table("actions");
	__PACKAGE__->add_columns(
		"id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		"name",
		{ data_type => "VARCHAR", is_nullable => 0, size => 128 },
		"description",
		{ data_type => "TEXT", is_nullable => 1, size => undef },
	);
	__PACKAGE__->set_primary_key("id");

MyApp::Schema::Roles

	package MyApp::Schema::Roles;

	...

	__PACKAGE__->table("roles");
	__PACKAGE__->add_columns(
		"id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		"name",
		{ data_type => "VARCHAR", is_nullable => 0, size => 128 },
	);
	__PACKAGE__->set_primary_key("id");

MyApp::Schema::UserRoles

	package MyApp::Schema::UserRoles;

	...

	__PACKAGE__->table("user_roles");
	__PACKAGE__->add_columns(
		"user_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		"role_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
	);
	__PACKAGE__->set_primary_key("user_id", "role_id");
	__PACKAGE__->belongs_to('role' => 'MyApp::Schema::Roles', 'role_id');

MyApp::Schema::RoleActions

	package MyApp::Schema::RoleActions;

	...

	__PACKAGE__->table("role_actions");
	__PACKAGE__->add_columns(
		"role_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		"action_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
	);
	__PACKAGE__->set_primary_key("role_id", "action_id");
	__PACKAGE__->belongs_to('role' => 'MyApp::Schema::Roles', 'role_id');
	__PACKAGE__->belongs_to('action' => 'MyApp::Schema::Actions', 'action_id');

MyApp::Schema::UserActions

	package MyApp::Schema::UserActions;

	...

	__PACKAGE__->table("user_actions");
	__PACKAGE__->add_columns(
		"user_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		"action_id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
	);
	__PACKAGE__->set_primary_key("user_id", "action_id");
	__PACKAGE__->belongs_to('action' => 'MyApp::Schema::Actions', 'action_id');

MyApp::Schema::Users

	package MyApp::Schema::Users;

	...

	__PACKAGE__->table("users");
	__PACKAGE__->add_columns(
		"id",
		{ data_type => "INTEGER", is_nullable => 0, size => undef },
		...
	);
	__PACKAGE__->set_primary_key("id");
	__PACKAGE__->has_many(map_user_role => 'MyApp::Schema::UserRoles', 'user_id');
	__PACKAGE__->many_to_many(user_roles => 'map_user_role', 'role');
	__PACKAGE__->has_many(map_user_action => 'MyApp::Schema::UserActions', 'user_id');
	__PACKAGE__->many_to_many(actions => 'map_user_action', 'action');

=head1 SEE ALSO

L<Catalyst::Plugin::Authentication>

L<Catalyst::Plugin::Authorization::Roles>

=head1 AUTHOR

Ido Perelmutter E<lt>ido50@yahoo.comE<gt>.

This module is based on the code for L<Catalyst::Plugin::Authorization::Roles>, created by Yuval Kogman <nothingmuch@woobling.org>.

=head1 COPYRIGHT & LICENSE

Copyright (c) 2008-2009 the aforementioned authors.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

