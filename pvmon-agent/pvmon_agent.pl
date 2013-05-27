#!/usr/bin/perl

# ------------------------------------------------------------------------------
# pvmon_agent.pl
# http://github.com/patrickviet/pvmon/pvmon-agent/
# runs events
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
use lib $basedir;

use PVMon::LoadConfig; # introduce $conf

# ------------------------------------------------------------------------------
# Initialize
$PVMon::LoadConfig::basedir = $basedir;
PVMon::LoadConfig::reload();


POE::Session->create(
	inline_states => {
		_start => \&start,
		plugin_run => \&plugin_run,
		plugin_close => \&plugin_close,
		plugin_stderr => \&plugin_stderr,
		plugin_stdout => \&plugin_stdout,
		sigcld => sub { $_[KERNEL]->sig_handled(); }

	},
);

sub start {

	$_[KERNEL]->sig('CLD','sigcld');

	foreach my $plugin_name (keys %{$conf->{run}}) {
		$_[KERNEL]->yield('plugin_run',$plugin_name);
	}
}

sub plugin_run {
	my ($heap,$arg) = @_[HEAP,ARG0];
	print "plugin_run $arg\n";

	my $wheel = POE::Wheel::Run->new(
		Program => $conf->{run}->{$arg},
		StdoutEvent => 'plugin_stdout',
		StderrEvent => 'plugin_stderr',
		CloseEvent => 'plugin_close',
	) or die $!;

	$heap->{wheel}->{$wheel->ID()} = [ $wheel, $arg ];
}

sub plugin_stdout {
	my ($heap,$arg,$wheel_id) = @_[HEAP,ARG0,ARG1];
	print $heap->{wheel}->{$wheel_id}->[1].": ".$arg."\n";
}

sub plugin_stderr {
	my ($heap,$arg,$wheel_id) = @_[HEAP,ARG0,ARG1];
	print $heap->{wheel}->{$wheel_id}->[1].": ".$arg."\n";
}



sub plugin_close {
	print "plugin close\n";
}

$poe_kernel->run();
