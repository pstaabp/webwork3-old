package DB::Schema::ResultSet::ProblemPool;
use strict;
use warnings;
use base 'DBIx::Class::ResultSet';

use Carp;
use Data::Dump qw/dd dump/;
use Scalar::Util qw/reftype/;

use DB::Utils qw/getCourseInfo parseCourseInfo getPoolInfo getPoolProblemInfo/;


=pod

=head1 DESCRIPTION

This is the functionality of a Course in WeBWorK.  This package is based on
<code>DBIx::Class::ResultSet</code>.  The basics are a CRUD for anything on the
global courses.

=cut

=pod
=head2 getAllProblemPools

This gets a list of all problems stored in the database in the <code>problems</codes> table.

=head3 input

<code>$as_result_set</code>, a boolean if the return is to be a result_set

=head3 output

An array of courses as a <code>DBIx::Class::ResultSet::Course</code> object
if <code>$as_result_set</code> is true.  Otherwise an array of hash_ref.

=cut

sub getAllProblemPools {
	my ($self, $as_result_set)  = @_;
	my @problem_pools = $self->search({},
		{prefetch => [qw/courses/]});
	return @problem_pools if $as_result_set;
	return map { {$_->get_inflated_columns,$_->courses->get_inflated_columns}; } @problem_pools;
}

=pod
=head2 getProblemPools

Get all problem pools for a given course

=cut

sub getProblemPools {
	my ($self,$course_info,$as_result_set) = @_;
	my $search_params = parseCourseInfo($course_info); ## return a hash of course info

	my $course_rs = $self->result_source->schema->resultset("Course");
	my $course = $course_rs->getCourse($course_info,1);


	my @pools = $self->search({'courses.course_id' => $course->course_id},{prefetch => [qw/courses/]});

	return \@pools if $as_result_set;
	return map { {$_->get_inflated_columns,$_->courses->get_inflated_columns}; } @pools;

}

####
#
# CRUD for a single ProblemPool
#
####
=pod
=head2 getProblemPool

Get a single problem pool for a given course

=cut

sub getProblemPool {
	my ($self,$course_pool_info,$as_result_set) = @_;
	my $course_info = getCourseInfo($course_pool_info);
	parseCourseInfo($course_info); ## return a hash of course info

	my $course_rs = $self->result_source->schema->resultset("Course");
	my $course = $course_rs->getCourse($course_info,1);

	my $search_info = getPoolInfo($course_pool_info);
	$search_info->{'courses.course_id'} = $course->course_id;

	my $pool = $self->find($search_info,{prefetch => [qw/courses/]});

	unless($pool) {
		my $pool_info = getPoolInfo($course_pool_info);
		my $course_name = $course->course_name;
		croak "The pool with info $pool_info in course $course_name does not exist";
	}

	return $pool if $as_result_set;
	return {$pool->get_columns,$pool->courses->get_columns};

}



=pod
=head2 addProblemPool

Add a problem pool for a given course

=cut

sub addProblemPool {
	my ($self,$course_info,$pool_params, $as_result_set) = @_;
	my $search_params = parseCourseInfo($course_info); ## return a hash of course info

	my $course_rs = $self->result_source->schema->resultset("Course");
	my $course = $course_rs->getCourse($course_info,1);
	my $course_name = $course->course_name;

	croak "The pool_name is missing from the parameters" unless defined($pool_params->{pool_name});

	my $existing_pool = $self->find(
						{
							'courses.course_id' => $course->course_id,
							pool_name => $pool_params->{pool_name}
						},{prefetch => [qw/courses/]});

	croak "The problem pool with name: \"$pool_params->{pool_name}\" in course $course_name already exists" if defined($existing_pool);

	my $pool_to_add =$self->new($pool_params);

	my $problem_pool = $course->add_to_problem_pools({$pool_to_add->get_columns});

	return $problem_pool if $as_result_set;
	return {$problem_pool->get_columns,$problem_pool->courses->get_columns};

}

=pod
=head2 updateProblemPool

updates the parameters of an existing problem pool

=cut

sub updateProblemPool {
	my ($self,$course_pool_info,$pool_params, $as_result_set) = @_;

	my $pool = $self->getProblemPool($course_pool_info,1);

	croak "The problem pool does not exist" unless defined($pool);

	# create a new problem pool to check for valid fields
	my $new_pool = $self->new($pool_params);

	my $updated_pool = $pool->update($pool_params);

	return $updated_pool if $as_result_set;
	return {$updated_pool->get_columns,$updated_pool->courses->get_columns};
}

=pod
=head2 updateProblemPool

updates the parameters of an existing problem pool

=cut

sub deleteProblemPool {
	my ($self,$course_pool_info,$pool_params, $as_result_set) = @_;

	my $pool = $self->getProblemPool($course_pool_info,1);

	croak "The problem pool does not exist" unless defined($pool);


	my $deleted_pool = $pool->delete();

	return $deleted_pool if $as_result_set;
	return {$deleted_pool->get_columns,$deleted_pool->courses->get_columns};
}

#####
#
# CRUD for PoolProblems, that is creating, retrieving, updating and deleting problem to existing ProblemPools
#
####

=pod
=head2 getPoolProblem

This gets a single problem out of a ProblemPool.  

=head3 arguments

=item *
hashref containing
=item -
course_id or course_name
=item -
problem_pool_id or pool_name
=item -
pool_problem_id or library_id or empty

=cut

sub getPoolProblem {
	my ($self,$course_pool_problem_info, $as_result_set) = @_;
	my $course_pool_info = {%{getCourseInfo($course_pool_problem_info)},%{getPoolInfo($course_pool_problem_info)}};
	
	my $problem_pool = $self->getProblemPool($course_pool_info,1);

	my @pool_problems  = $problem_pool->search_related("pool_problems",getPoolProblemInfo($course_pool_problem_info))->all; 

	if (scalar(@pool_problems) == 1 ) {
		return $pool_problems[0] if $as_result_set;
		return {$pool_problems[0]->get_columns}; 
	} else { # pick a random problem. 
	   my $prob = $pool_problems[ rand @pool_problems ];
		 return $prob if $as_result_set;
		 return {$prob->get_columns};
	}
}


=pod
=head2 addProblemToPool

This adds a problem as a hashref to an existing problem pool.

=cut

use JSON; 

sub addProblemToPool {
	my ($self,$course_pool_info,$problem_params, $as_result_set) = @_;

	my $pool = $self->getProblemPool($course_pool_info,1);
	croak "The problem pool does not exist" unless defined($pool);

	my $course_rs = $self->result_source->schema->resultset("Course");
	my $course = $course_rs->find({course_id => $pool->course_id});

	my $problem_pool_rs = $self->result_source->schema->resultset("PoolProblem");
	$problem_params->{problem_pool_id} = $pool->problem_pool_id; 
	my $pool_problem = $problem_pool_rs->new($problem_params);

	my $added_problem = $pool->add_to_pool_problems({$pool_problem->get_columns}); 

	return $added_problem if $as_result_set;
	return {$added_problem->get_columns};

}


=pod
=head2 updatePoolProblem

updated an existing problem to an existing ProblemPool in a course

=head3 arguments
=item *
hashref containing
=item -
course_id or course_name
=item -
pool_name or problem_pool_id
=item -
library_id or ???
=item *
hashref containing information about the Problem.

=cut


sub updatePoolProblem {
	my ($self,$course_pool_problem_info, $prob_params, $as_result_set) = @_;
	my $prob = $self->getPoolProblem($course_pool_problem_info,1);

	croak "The pool problem with info $course_pool_problem_info does not exist." unless defined($prob); 

	my $problem_pool_rs = $self->result_source->schema->resultset("PoolProblem");
	my $prob_to_update = $problem_pool_rs->new($prob_params);

	my $prob2 = $prob->update({$prob_to_update->get_columns});
	return $prob2 if $as_result_set;
	return {$prob2->get_columns};
}

1;