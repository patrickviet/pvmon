package PVMon::RessourceManager;


use warnings;
use strict;
use POE;
use PVMon::LoadConfig;
use JSON::PP;

my $jsoncoder = JSON::PP->new->ascii->allow_nonref;

sub new {
  my $class = shift;
  
  return bless {
    running => {},
    queue => {}  
  },$class;
}

sub reload {

  my ($obj,$msg) = @_;
  if($msg) { print "reload: $msg\n"; } 
  my $queue = $obj->{queue};
  
  PVMon::LoadConfig::reload();
  
  ## so here I do a big 'diff' which is kinda fun ...
  ## if cmd or exec_interval change then I'll put next run at now
  
  # delete non existing stuff
  foreach my $task_id (keys %$queue) {
    if(!exists $conf->{$task_id}) {
      delete $queue->{$task_id};
      delete $obj->{running}->{$task_id}; # if it's running that will take care of it ...
    }
  }
  
  # add new stuff and update existing
  foreach my $task_id (keys %$conf) {
    next if $task_id eq 'base'; # ignore base config that's not a plugin exec
    
    if(exists $queue->{task_id}) {
      my $next_run = 0;
      if ($queue->{$task_id}->{exec_interval} eq $conf->{$task_id}->{exec_interval}
        && $queue->{$task_id}->{exec_interval} eq $queue->{$task_id}->{exec_interval}) {

        $next_run = $queue->{$task_id}->{next_run};

      }
      
      %{$queue->{$task_id}} = %{$conf->{$task_id}}; 
      $queue->{$task_id}->{next_run} = $next_run; 
             
    
    } else {
      %{$queue->{$task_id}} = %{$conf->{$task_id}}; # defer to make a real copy
      $queue->{$task_id}->{next_run} = 0;          
    }    
  }
  
  
}

sub already_running {
  my ($obj,$task_request) = @_;
  if(exists $obj->{running}->{$task_request->{service}})  { return 1; }
}

sub task_register {
  my ($obj,$task) = @_;
  $obj->{running}->{$task->ID} = $task;
  $task->{resman} = $obj;
  $task->run($obj);
}

sub can_run_new_task {
  my $obj = shift;
  if(scalar keys %{$obj->{running}} < $conf->{base}->{max_simultaneous_tasks}) {
    return 1;
  }
}

sub get_queue {
  my $obj = shift;
  my $queue = [];
  my $now = time();
  
  # not fast but I won't have millions either so it's OK I guess ...
  foreach my $task_id (keys %{$obj->{queue}}) {
    my $task_request = $obj->{queue}->{$task_id};
    if($task_request->{next_run} < $now) {
      # must run.
      $task_request->{service} = $task_id;
      push @$queue, $task_request;
    }
  }
  
  return $queue;
} 
  
sub task_unregister {
  my ($obj,$task) = @_;
  my $task_id = $task->ID;
  delete $obj->{running}->{$task_id};
  
  $obj->{queue}->{$task_id}->{next_run} = time() + $obj->{queue}->{$task_id}->{exec_interval};
  
  #FIXME
  
  my $tmpfile;
  my $tmpdir = $conf->{base}->{tmpdir};
  die unless $tmpdir;
  if(!-d $tmpdir) { system("mkdir -p $tmpdir"); }
  
  do {
    $tmpfile = "$tmpdir/pvmon.push.".time().".$$.".rand();  
  }
  while(-f $tmpfile);
  
  use Data::Dumper;
  print Dumper($task->{ret});
  
  open my $fh, ">$tmpfile" or die $!;
  print $fh $jsoncoder->encode($task->{ret});
  close $fh;
  
}

1;