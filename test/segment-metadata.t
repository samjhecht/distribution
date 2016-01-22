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
  analysisTypes => ['INTERVAL']
});

delete $druid_result_minus_id->[0]{id};

my $druid_expected_minus_id = [{
  "columns" => {
     "__time" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG", "hasMultipleValues" => $JSON::false},
     "added" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG", "hasMultipleValues" => $JSON::false},
     "channel" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "cityName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "comment" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "count" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG", "hasMultipleValues" => $JSON::false},
     "countryIsoCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "countryName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "deleted" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG", "hasMultipleValues" => $JSON::false},
     "delta" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "LONG", "hasMultipleValues" => $JSON::false},
     "isAnonymous" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "isMinor" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "isNew" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "isRobot" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "isUnpatrolled" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "metroCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "namespace" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "page" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "regionIsoCode" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "regionName" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "user" => {"cardinality" => 0, "errorMessage" => undef, "size" => 0, "type" => "STRING", "hasMultipleValues" => $JSON::false},
     "user_unique" => {"cardinality" => undef, "errorMessage" => undef, "size" => 0, "type" => "hyperUnique", "hasMultipleValues" => $JSON::false}
  },
  "intervals" => ["2015-09-12T00:00:00.000Z/2015-09-13T00:00:00.000Z"],
  "numRows" => 39244,
  "size" => 0
}];

eq_or_diff($druid_result_minus_id, $druid_expected_minus_id, 'druid query results are as expected');
