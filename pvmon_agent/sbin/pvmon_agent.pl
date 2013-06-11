#!/usr/bin/perl

# ------------------------------------------------------------------------------
# pvmon_agent.pl
# http://github.com/patrickviet/pvmon/pvmon-agent/
#
# This is the helper/runner script
# it relaunches stuff after two seconds if it dies...
#
# Deps: Config::Tiny, POE
#
# ------------------------------------------------------------------------------ 

use warnings;
use strict;
use POE qw(Wheel::Run);

# ------------------------------------------------------------------------------
# Must run as root
#die 'must run as root' unless $< == 0;

# ------------------------------------------------------------------------------
# Get current path - must be run before everything else - hence the BEGIN func
# The used libraries are part of perl core.
our $basedir;
BEGIN {
	use POSIX qw(setsid);
	use Cwd qw(realpath);
	use File::Basename;
	$basedir = dirname(realpath(__FILE__));


	# daemonize code here .... no options. This is dirty ha ha ha
	if(@ARGV) {
		if($ARGV[0] eq '-D') {

			# daemonize
			chdir($basedir) or die "Can't chdir to $basedir: $!";

			open STDIN,  '/dev/null'  or die "Can't read /dev/null: $!";
			open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
			defined( my $pid = fork ) or die "Can't fork: $!";
			exit if $pid;
			setsid or die "Can't start a new session: $!";

			print STDERR "daemonize $0: New pid is $$\n";
			open STDERR, ">& STDOUT" or die "Can't dup logfile: $!";

		} else {
			print "usage: $0 [ -D ]\n";
			exit 1;
		}
	}
}

# ------------------------------------------------------------------------------
# Internal libs (relative path...)
use lib '../'.$basedir;

use PVMon::LoadConfig; # introduce $conf

# ------------------------------------------------------------------------------
# Initialize
$PVMon::LoadConfig::basedir = $basedir;
PVMon::LoadConfig::reload();

chdir($basedir) or die "unable to go to basedir $basedir: $!";

POE::Session->create(
	inline_states => {
		_start => \&start,
		plugin_run => \&plugin_run,
		plugin_close => \&plugin_close,
		plugin_stderr => \&plugin_stderr,
		plugin_stdout => \&plugin_stdout,
		sigcld => sub { $_[KERNEL]->sig_handled(); },
		sigterm => \&sigterm,

	},
);

sub start {
	my $kernel = $_[KERNEL];

	$kernel->sig('CLD','sigcld');

	# all these signals just stop the watcher and its processes
	$kernel->sig('TERM','sigterm');
	$kernel->sig('INT','sigterm');
	$kernel->sig('HUP','sigterm');

	# run the plugins
	foreach my $plugin_name (keys %{$conf->{run}}) {
		$kernel->yield('plugin_run',$plugin_name);
	}
}

sub plugin_run {
	my ($heap,$plugin_name) = @_[HEAP,ARG0];
	print "plugin_run $plugin_name\n";

	my $wheel = POE::Wheel::Run->new(
		Program => $conf->{run}->{$plugin_name},
		StdoutEvent => 'plugin_stdout',
		StderrEvent => 'plugin_stderr',
		CloseEvent => 'plugin_close',
	) or die $!;

	$heap->{wheel}->{$wheel->ID()} = [ $wheel, $plugin_name ];
}

sub plugin_stdout {
	my ($heap,$output,$wheel_id) = @_[HEAP,ARG0,ARG1];
	print "STDOUT ".$heap->{wheel}->{$wheel_id}->[1].": ".$output."\n";
}

sub plugin_stderr {
	my ($heap,$output,$wheel_id) = @_[HEAP,ARG0,ARG1];
	print "STDERR ".$heap->{wheel}->{$wheel_id}->[1].": ".$output."\n";
}



sub plugin_close {
	my ($kernel,$heap,$wheel_id) = @_[KERNEL,HEAP,ARG0];
	my $wheel_data = delete $heap->{wheel}->{$wheel_id};
	my ($wheel,$plugin_name) = @$wheel_data;
	print "plugin close: $plugin_name\n";


	print "relaunching plugin $plugin_name in 2sec\n";
	$kernel->delay_set('plugin_run',2,$plugin_name);
}


sub sigterm {
	my ($kernel,$heap) = @_[KERNEL,HEAP];

	print "terminating...\n";

	foreach my $wheel_id (keys %{$heap->{wheel}}) {
		print "killing ".$heap->{wheel}->{$wheel_id}->[1]." (PID: ".$heap->{wheel}->{$wheel_id}->[0]->PID.")\n";
		$heap->{wheel}->{$wheel_id}->[0]->kill();
	}
}

$poe_kernel->run();
