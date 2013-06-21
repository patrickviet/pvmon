#!/usr/bin/perl

# ------------------------------------------------------------------------------
# pvmon_agent_pushd.pl
# http://github.com/patrickviet/pvmon/pvmon-agent/
# sends events
#
# Deps: WWW::Curl, Config::Tiny
#
# ------------------------------------------------------------------------------ 


# Standard libs
use warnings;
use strict;
use WWW::Curl::Easy;

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

# ---
# JSON
eval {
	require JSON;
	JSON->import(qw(decode_json));
	print "loaded JSON module\n";
};
if($@) {
	eval {
		require JSON::PP;
		JSON::PP->import(qw(decode_json));
		print "loaded JSON::PP module\n";
	};
	if($@) {
		die "unable to load JSON or JSON::PP";
	}
}

# ------------------------------------------------------------------------------
# Internal libs (relative path...)
use lib $basedir.'/..';
use PVMon::LoadConfig; # introduces the $conf variable ...

# ------------------------------------------------------------------------------
# Initialize
$PVMon::LoadConfig::basedir = $basedir;
PVMon::LoadConfig::reload();


# ------------------------------------------------------------------------------

$| = 1;
my $curl = WWW::Curl::Easy->new;
$curl->setopt(CURLOPT_CAINFO, $conf->{notifier}->{ssl_ca_cert});
$curl->setopt(CURLOPT_SSLCERT, $conf->{notifier}->{ssl_client_cert});
$curl->setopt(CURLOPT_SSLKEY , $conf->{notifier}->{ssl_client_key});
$curl->setopt(CURLOPT_SSL_VERIFYPEER, 1);
$curl->setopt(CURLOPT_POST, 1);

print $conf->{notifier}->{ssl_ca_cert}."\n";

while(1) {
	my @to_delete = ();
	my @content = ();
	my $next_wait = 1;

	if(!-d $conf->{base}->{tmpdir}) { system("mkdir ".$conf->{base}->{tmpdir}); }
	
	opendir my $dh, $conf->{base}->{tmpdir} or die "unable to open queue dir: $!";
	while(my $file = readdir $dh) {
		$file = $conf->{base}->{tmpdir}.'/'.$file;
		next unless -f $file;
		
		print "found file $file\n";
		my $buf = "";
		open my $fh, $file or die $!;
		while(<$fh>) { $buf .= $_; }
		close $fh;

		eval {
			decode_json($buf);
		};
		if($@) {
			print "invalid JSON in file $file. ";
			my @st = stat($file);
			if(($st[9] + 3600) < scalar time()) {
				print " deleting because it's older than an hour\n";
				unlink $file;
			} else {
				print " keeping because it's more recent an hour\n";
			}
			next;
		}

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
	
		my $response_content;
		$curl->setopt(CURLOPT_WRITEDATA,\$response_content);
		$curl->setopt(CURLOPT_URL, $conf->{notifier}->{url});
		$curl->setopt(CURLOPT_POSTFIELDS, '['.join(',',@content).']');

		my $retcode = $curl->perform();

		if($retcode == 0) {
			# we got some stuff

			if($response_content eq "OK\n") {
				foreach my $file (@to_delete) { unlink $file or die "unable to delete $file: $!"; }
			} else {

				print "unable to push (ERR: ".substr($response_content,0,500).")\n";
				$next_wait = 5;

				if($response_content =~ m/^ERR/) {
					$next_wait = 1;
				}
			}


		} else {
			# we got an uncool error
			print "we got some error. retcode: $retcode. err:".$curl->strerror($retcode)." ".$curl->errbuf."\n";
			$next_wait = 2;
		}
	}
	sleep($next_wait);
}
