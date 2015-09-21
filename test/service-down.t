#!/usr/bin/env perl

use strict;
use warnings;

use ImplyTest;
use JSON;
use Test::Differences;
use Test::More tests => 4;

my $iap = ImplyTest->new;
my $dir = $iap->dir;

# Start up services
ok($iap->start('quickstart'), 'started');

# Load example data
my $taskok = $iap->runtask(JSON::decode_json(scalar qx[cat \Q$dir\E/quickstart/wikiticker-index.json]));
ok($taskok, 'example index task');

# Wait for data to load
is($iap->await_load('wikiticker'), 100, 'example loading complete');

# Shut down services
ok($iap->down, 'down command stopped services');
