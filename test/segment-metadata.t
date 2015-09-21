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

# Direct Druid query
my $druid_result_minus_id = $iap->query_druid({
  queryType => 'segmentMetadata',
  dataSource => 'wikiticker',
  merge => JSON::true,
  analysisTypes => []
});

delete $druid_result_minus_id->[0]{id};

my $druid_expected_minus_id = [{
  "columns" => {
     "__time" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG"},
     "added" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG"},
     "channel" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "cityName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "comment" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "count" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG"},
     "countryIsoCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "countryName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "deleted" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG"},
     "delta" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG"},
     "isAnonymous" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "isMinor" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "isNew" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "isRobot" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "isUnpatrolled" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "metroCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "namespace" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "page" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "regionIsoCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "regionName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "user" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING"},
     "user_unique" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "hyperUnique"}
  },
  "intervals" => ["2015-09-12T00:00:00.000Z/2015-09-13T00:00:00.000Z"],
  "size" => 0
}];

eq_or_diff($druid_result_minus_id, $druid_expected_minus_id, 'druid query results are as expected');
