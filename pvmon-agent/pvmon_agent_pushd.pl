#!/usr/bin/perl

# ------------------------------------------------------------------------------
# pvmon_agent_pushd.pl
# http://github.com/patrickviet/pvmon/pvmon-agent/
# sends events
#
# Deps: HTTP::Tiny, Config::Tiny
#
# ------------------------------------------------------------------------------ 


# Standard libs
use warnings;
use strict;
use HTTP::Tiny;

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

# ------------------------------------------------------------------------------
# Initialize
$PVMon::LoadConfig::basedir = $basedir;
PVMon::LoadConfig::reload();


# ------------------------------------------------------------------------------

my $http = HTTP::Tiny->new;

while(1) {
	my @to_delete = ();
	my @content = ();
	my $next_wait = 1;

	opendir my $dh, $conf->{base}->{tmpdir} or die "unable to open queue dir: $!";
	while(my $file = readdir $dh) {
		$file = $conf->{base}->{tmpdir}.'/'.$file;
		next unless -f $file;
		
		print "found file $file\n";
		my $buf = "";
		open my $fh, $file or die $!;
		while(<$fh>) { $buf .= $_; }
		close $fh;

		# we have the buffer
		push @to_delete,$file;
		push @content,$buf;

		if(scalar @content >= $conf->{notifier}->{post_chunk_size}) {
			$next_wait = 0;
			last;	
		}
		
	}
	closedir $dh;


	if(scalar @content) {
		my $params = { content => '['.join(',',@content).']', };
	

		my $response = $http->request('POST', $conf->{notifier}->{url}, $params);

		if($response->{content} eq "OK\n") {
			foreach my $file (@to_delete) { unlink $file or die "unable to delete $file: $!"; }
		} else {
			print "unable to push\n";
			$next_wait = 5;
		}
	}
	sleep($next_wait);

}
