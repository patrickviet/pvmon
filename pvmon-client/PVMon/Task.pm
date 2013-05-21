package PVMon::Task;

# ------------------------------------------------------------------------------
# Structure of a Task request
#
# name = a name... can be in the format name/subname
# cmd = the command to run
# format = json (future=nagios)
# interval = interval in seconds
# tags = list separated by commas. optional. will be automatically added...
# description = freeform text
# timeout = in seconds, time before it fails and generates a default fail event
 

# Specific task states
# Transient states: next_run
#		 

# ------------------------------------------------------------------------------

use warnings;
use strict;
use POE qw(Wheel::Run);

sub new {
	my ($class,$task_request) = @_;
	return bless {
		req => $task_request,	
	},$class;	
}

sub ID {
	my $obj = shift;
	return $obj->{req}->{service};
}

sub run {
	my ($obj,$resman) = @_;
	# the ressource manager must pass itself as a param
	
	$obj->{resman} = $resman;
	
	$obj->{session} = POE::Session->create(
		object_states => [ $obj => [ qw(_start _stop task_run task_stdout task_stderr task_close timeout)]],	
	);
}

sub _start {
	my ($obj,$kernel) = @_[OBJECT,KERNEL];
	$obj->{cmd} = $obj->{req}->{cmd};
	$kernel->yield('task_run');
}

sub _stop {
	$_[0]->free_myself();
}

sub _default {
	print "default\n";
}

sub task_run {
	my ($obj,$kernel) = @_[OBJECT,KERNEL];
	$obj->{stdout} = [],
	$obj->{stderr} = "",

	# check that it can run ...	
	my @sp = split(/\ /, $obj->{cmd});
	if (! -x $sp[0]) {
		if(-x 'plugins/'.$sp[0]) {
			$obj->{cmd} = 'plugins/'.$obj->{cmd};
		} else {
			$obj->{stderr} = $sp[0]." is not executable";
			return $kernel->yield('task_close');			
		}
	}
	
	my $wheel;
	
	eval {
		$wheel = POE::Wheel::Run->new(
			Program => $obj->{cmd},
			StdoutEvent => 'task_stdout',
			StderrEvent => 'task_stderr',
			CloseEvent => 'task_close',
		) or $obj->{stderr} = "ERR CRIT - error at lauch: $!";
	};
	
	if($@) {
		$obj->{stderr} = "ERR CRIT - error at launch: $@";	
		return $kernel->yield('task_close');
	}
	
	if (!$wheel) {
		$obj->{stderr} = "no wheel";
		return $kernel->yield('task_close');
	}
	
	$obj->{wheel} = $wheel;
}

sub timeout {
	my ($obj,$kernel) = @_[OBJECT,KERNEL];
	$obj->{stderr} .= "timeout!!!! (".$obj->{req}->{timeout}.")";
	$kernel->yield('task_close');
}

sub task_stdout {
	my ($obj,$kernel,$output) = @_[OBJECT,KERNEL,ARG0];
	#$obj->{stdout} .= $output;
	push @{$obj->{stdout}},$output;
}

sub task_stderr {
	my ($obj,$kernel,$output) = @_[OBJECT,KERNEL,ARG0];
	$obj->{stderr} .= $output;
}


sub task_close {
	my ($obj,$kernel) = @_[OBJECT,KERNEL];
	$obj->{wheel} = undef;
	 
	# we are basically generating a task result.
	# stdout is in the format: one line = one result
	# I would like JSON but it means more deps so we keep it simple:
	# <key> - space - <value> <carriage return>. I also trim any kind of space etc
	
	my $ret = { stderr => $obj->{stderr} };
	
	# compute stdout	 
	foreach (@{$obj->{stdout}}) {
		if( m/^([A-Za-z0-9\_\-\/\.]+)([\ ]+)(.*)/ ) {
			$ret->{$1} = $3;			
		}		
	}
	
	$obj->{ret} = $ret;
	
	if(!exists $ret->{time}) { $ret->{time} = time(); }

	# fill other values
	foreach my $k(keys %{$obj->{req}}) {
		if(!exists $ret->{$k}) {
			$ret->{$k} = $obj->{req}->{$k};
		}
	}


	# FIXME
	# kill timeout 

	$obj->free_myself();
	
	$kernel->post('main_loop','basic_loop');
}


sub free_myself {
	my $obj = shift;
	if($obj->{resman}) {
		$obj->{resman}->task_unregister($obj);
		$obj->{resman} = undef;
	}
	
	$obj->{session} = undef;
	$obj->{wheel} = undef;	
}

1;