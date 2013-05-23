#!/usr/bin/perl

# ------------------------------------------------------------------------------
# pvmon_run_tasks.pl
# http://github.com/patrickviet/pvmon/pvmon-client/
# runs events
#
# Deps: Config::Tiny, POE
#
# ------------------------------------------------------------------------------ 


# Standard libs
use warnings;
use strict;
use POE;


# ------------------------------------------------------------------------------
# Must run as root
die 'must run as root' unless $< == 0;

# ------------------------------------------------------------------------------
# Get current path - must be run before everything else - hence the BEGIN func
# The used libraries are part of perl core.
our $basedir;
BEGIN {
	use Cwd qw(realpath);
	use File::Basename;
	$basedir = dirname(realpath(__FILE__));
}

# ------------------------------------------------------------------------------
# Internal libs (relative path...)
use lib $basedir;
use PVMon::LoadConfig; # introduces the $conf variable ...
use PVMon::RessourceManager;
use PVMon::Task;

# ------------------------------------------------------------------------------
# Initialize
$PVMon::LoadConfig::basedir = $basedir;
PVMon::LoadConfig::reload();
my $resman = PVMon::RessourceManager->new();



# Basic loop
# This is not written in typical idiomatic perl
# because I want anyone from another language background to easily read it

sub basic_loop {
	if ($resman->can_run_new_task()) {
		my $queue = $resman->get_queue();
		if (scalar @$queue) {
			foreach my $task_request (@$queue) {
				if($resman->can_run_new_task()) {
					if(!$resman->already_running($task_request)) {
						my $task = PVMon::Task->new($task_request);
						$resman->task_register($task); # as the task is registered
						# the resman will record it, index it, run it...
					}
				}
			}
		} 
	}
}



# The POE event manager that handles all this...
POE::Session->create(
	inline_states => {
		_start 			=> \&start,
		_stop 			=> sub { print "stopped\n"; },
		basic_loop 		=> \&basic_loop,
		run_basic_loop 	=> \&run_basic_loop,
		
		sigchld 		=> sub { $_[KERNEL]->sig_handled(); }, # reap children processes
		sighup 			=> \&sighup,
		auto_reload 	=> \&auto_reload,
	}
);

# ------------------------------------------------------------------------------
#checkpid
my $pidfile = $conf->{base}->{pidfile};
my $newpid;
END { if ($newpid) { unlink $pidfile or die "unable to delete $pidfile: $!"; } }

if (-f $pidfile) {
	open PIDFILE, "<$pidfile" or die "unable to open pidfile: $!";
	my $pid = <PIDFILE>;
	chomp $pid;
	if (($pid) and (kill(0,$pid))) {
		# already running
		exit 0;
	} else {
		unlink $pidfile or die "unable to delete $pidfile: $!";
		kill 9,$pid;
	}
}

$newpid = $$;
open PIDFILE, ">$pidfile" or die "unable to open pidfile: $!";
print PIDFILE "$newpid\n";
close PIDFILE;

# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
sub start {
	my $kernel = $_[KERNEL];
	$kernel->yield('auto_reload');
	$kernel->yield('run_basic_loop');

	$kernel->sig('HUP', 'sighup');
	$kernel->sig('CHLD', 'sigchld');
	
	$kernel->alias_set('main_loop');
}

sub run_basic_loop {
	my $kernel = $_[KERNEL];
	# we run the basic loop every two seconds
	$kernel->yield('basic_loop');
	$kernel->delay_set('run_basic_loop',1);	
}

sub _child {
	my ($kernel,$create_or_lose) = @_[KERNEL,ARG0];
	# RESPAWN ON LOSE
	if ($create_or_lose eq 'lose') {
		$kernel->yield('basic_loop');
	}
	$kernel->sig_handled();
}

sub sighup {
	my $kernel = $_[KERNEL];
	$resman->reload("Got SIGHUP");
	$kernel->sig_handled();
}

sub auto_reload {
	my $kernel = $_[KERNEL];
	my $delay = $conf->{base}->{auto_reload_delay};
	#mylog(LOG_NOTICE,"automatic reload after $delay sec");
	$resman->reload("Auto Reload after $delay secs");
	$kernel->delay_set('auto_reload',$delay);
}

# last but not least
$poe_kernel->run();
