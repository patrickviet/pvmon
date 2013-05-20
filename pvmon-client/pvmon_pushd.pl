#!/usr/bin/perl

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

