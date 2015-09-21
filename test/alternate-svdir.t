#!/usr/bin/env perl

use strict;
use warnings;

use File::Temp qw/tempdir/;
use ImplyTest;
use JSON;
use Test::Differences;
use Test::More tests => 5;

my $vardir = tempdir(CLEANUP => 1);
my $iap = ImplyTest->new(vardir => "$vardir");
my $dir = $iap->dir;

# Start up services
ok($iap->start('quickstart'), 'started');

# Verify var is a symlink
ok(-l "$dir/var", "var/ is a symlink");
is(readlink "$dir/var", "$vardir", "var/ links to our tmpdir");

# Load example data
my $taskok = $iap->runtask(JSON::decode_json(scalar qx[cat \Q$dir\E/quickstart/wikiticker-index.json]));
ok($taskok, 'example index task');

# Wait for data to load
is($iap->await_load('wikiticker'), 100, 'example loading complete');

# Unconfuse tester
$? = 0;
