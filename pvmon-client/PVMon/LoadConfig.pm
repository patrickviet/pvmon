package PVMon::LoadConfig;

use warnings;
use strict;
use Exporter;
use Config::Tiny;

use vars qw($conf);
our @ISA = qw(Exporter);
our @EXPORT = qw($conf);

## improved version: reads files from other directories and shit.

## FIXME: I set base directory as /home/pviet/monperl/pvmon-client
my $basedir = '/home/pviet/monperl/pvmon-client';

reload();

sub reload {
  my $oldconf = $conf;
  $conf = Config::Tiny->read($basedir.'/pvmon.conf');
  if(!$conf) { $conf = $oldconf; }

  my $confd = $basedir.'/pvmon.conf.d';

  if (-d $confd) {
    opendir(my $dh, $confd) or die "unable to open dir $confd: $!";
    foreach my $file (readdir $dh) {
      next unless -f "$confd/$file";
      next unless $file =~ m/(.*)\.conf$/; # only get .conf files ...

      # replacing stuff with slashes because that's how graphite automatically
      # splits directories/sections ...

      my $default_service = $1;
      my ($default_service_base,$default_service_sub) = ($default_service,'default');
      
      if($default_service =~ m/(.*)\.([^\.]+)$/) {
      
        ($default_service_base,$default_service_sub) = ($1,$2);
        $default_service =~ s/\./\\/g; # replace dot by slash        
      }
      
      
      my $localconf = Config::Tiny->read("$confd/$file") or next;


      # auto fill in ----
      if(exists $localconf->{_}) {
        $localconf->{$default_service_base.'/'.$default_service_sub} = delete $localconf->{_};
      }

      foreach my $service (keys %$localconf) {
        if (!($service =~ m/\//) and $service ne 'base') {
          $localconf->{$default_service_base.'/'.$service} = delete $localconf->{$service};
        }
      }
        
      
      override($conf,$localconf);
    }
    
    closedir($dh); 
  } 
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
