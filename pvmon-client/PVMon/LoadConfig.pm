package PVMon::LoadConfig;

use warnings;
use strict;
use Exporter;
use Config::Tiny;
use Carp qw(croak carp);

use vars qw($conf $conf_tasks $basedir);
our @ISA = qw(Exporter);
our @EXPORT = qw($conf $conf_tasks);

## improved version: reads files from other directories and stuff
## You must set $PVMon::LoadConfig::basedir before running a reload


sub reload {
	die 'needs basedir' unless -d $basedir;

	# first part: the 'generic' configuration
	# ---------------------------------------
	my $new_conf = Config::Tiny->read("$basedir/pvmon.conf");
	if(!$new_conf) {
		carp "unable to load config file $basedir/pvmon.conf: $!";
		if($conf) {
			carp "keeping current config running";
			return;
		} else {
			# this is a first run
			croak "interrupting startup";
		}
	}

	my $new_conf_local = Config::Tiny->read("$basedir/pvmon.local.conf");
	if($new_conf_local) {
		override($new_conf,$new_conf_local);
	} else {
		carp "unable to load local config file $basedir/pvmon.local.conf: $!";
	}

	$conf = $new_conf;

	# hostname
	if(!exists $conf->{base}->{host}) {
		my $host = `hostname`;
		chomp($host);
		$conf->{base}->{host} = $host;
	}


	# second part: the 'task' configuration
	# -------------------------------------

	my $new_conf_tasks = Config::Tiny->read("$basedir/pvmon.tasks.conf");
	if(!$new_conf_tasks) {
		carp "unable to load config file $basedir/pvmon.tasks.conf: $!";
		if($conf_tasks) {
				carp "keeping current running config";
			} else {
				croak "interrupting startup";
			}
	}

	

	# add 'special task': the hello
	$new_conf_tasks->{hello} = {
		'cmd' => '/bin/cat /dev/null',
		'exec_interval' => $conf->{base}->{hello_interval}, # this means it times out after 2x this
		'metric' => 0, state => 'ok',
		'rs_length' => 1,
		'rs_max_warn' => 1,
		'rs_max_crit' => 1,
		'rs_persistent' => 1, # make it persistent: stays there until deleted manually
	};

	my $conf_tasks_d = $basedir.'/pvmon.tasks.conf.d';

	if (-d $conf_tasks_d) {
		opendir(my $dh, $conf_tasks_d) or die "unable to open dir $conf_tasks_d: $!";
		foreach my $file (readdir $dh) {
			next unless -f "$conf_tasks_d/$file";
			next unless $file =~ m/(.*)\.conf$/; # only get .conf files ...

			# replacing stuff with slashes because that's how graphite automatically
			# splits directories/sections ...

			my $default_service = $1;
			my ($default_service_base,$default_service_sub) = ($default_service,'default');
			
			if($default_service =~ m/(.*)\.([^\.]+)$/) {
			
				($default_service_base,$default_service_sub) = ($1,$2);
				$default_service =~ s/\./\\/g; # replace dot by slash				
			}
			
			
			my $localconf = Config::Tiny->read("$conf_tasks_d/$file");

			if ($localconf) {
				# auto fill in ----
				if(exists $localconf->{_}) {
					$localconf->{$default_service_base.'/'.$default_service_sub} = delete $localconf->{_};
				}

				foreach my $service (keys %$localconf) {
					if (!($service =~ m/\//) and $service ne 'base') {
						$localconf->{$default_service_base.'/'.$service} = delete $localconf->{$service};
					}
				}
					
				
				override($new_conf_tasks,$localconf);
			
			} else {
				carp "unable to load $conf_tasks_d/$file: $!";
			}
		}
		
		closedir($dh); 
	}

	$conf_tasks = $new_conf_tasks;

}



sub override {
	my ($elem1,$elem2) = @_;

	if (ref($elem2) eq 'ARRAY') {
		foreach (@$elem2) {
			if (ref($_)) {
				override($elem1->[$_],$elem2->[$_]);
				# attention il n'y a pas de deep copy!!
			} else {
				$elem1->[$_] = $elem2->[$_];
			}
		}
	} elsif (ref ($elem2) eq 'HASH' or ref ($elem2) eq 'Config::Tiny') {
		foreach (keys %$elem2) {
			if (ref($elem2->{$_})) {
				if(ref($elem1->{$_})) {
					override($elem1->{$_},$elem2->{$_});
				} else {
					$elem1->{$_} = deep_copy($elem2->{$_});
				}
			} else {
				$elem1->{$_} = $elem2->{$_};
			}
		}
	} else {
		die "drole de ref! $_?";
	}
}

sub deep_copy {
	my $this = shift;
	if (not ref $this) {
		$this;
	} elsif (ref $this eq "ARRAY") {
		[map deep_copy($_), @$this];
	} elsif (ref $this eq "HASH") {
		+{map { $_ => deep_copy($this->{$_}) } keys %$this};
	} else { die "what type is $_?" }
}


1;
