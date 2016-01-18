#!/usr/bin/env perl

use strict;
use warnings;

use File::Temp qw/tempfile/;
use ImplyTest;
use JSON;
use POSIX qw/strftime/;
use Test::Differences;
use Test::More tests => 6;

my $iap = ImplyTest->new;
my $dir = $iap->dir;

# POST-HANDOFF test:
# Reduce segmentGranularity, windowPeriod, and firehoseGracePeriod so handoff happens faster.
my $server_json = JSON::decode_json(
  do { local $/; open my $fh, "<", "$dir/conf-quickstart/tranquility/server.json" or die; <$fh> }
);
$server_json->{'dataSources'}{'metrics'}{'spec'}{'dataSchema'}{'granularitySpec'}{'segmentGranularity'} = 'minute';
$server_json->{'dataSources'}{'metrics'}{'spec'}{'tuningConfig'}{'windowPeriod'} = 'PT1M';
$server_json->{'properties'}{'druidBeam.firehoseGracePeriod'} = 'PT0S';
open my $fh, ">", "$dir/conf-quickstart/tranquility/server.json";
print $fh JSON::encode_json($server_json);
close $fh or die;

# Start up services
ok($iap->start('quickstart'), 'started');

# Load example data
my $ts = strftime("%Y-%m-%dT%H:%M:%S.000Z", gmtime(time));
my $rsp = $iap->post_tranq('metrics', <<EOT);
{"unit": "milliseconds", "http_method": "GET", "value": 60, "timestamp": "$ts", "http_code": "200", "page": "/list", "metricType": "request/latency", "server": "www1.example.com"}
{"unit": "milliseconds", "http_method": "GET", "value": 1, "timestamp": "$ts", "http_code": "200", "page": "/", "metricType": "request/latency", "server": "www2.example.com"}
{"unit": "milliseconds", "http_method": "GET", "value": 61, "timestamp": "$ts", "http_code": "200", "page": "/get/68", "metricType": "request/latency", "server": "www4.example.com"}
EOT

eq_or_diff($rsp, {result => {received => 3, sent => 3}}, 'metrics sent');

# Wait for data to be handed off
is($iap->await_load('metrics'), 100, 'metrics handoff complete');

# Direct Druid query
my $druid_result = $iap->query_druid(JSON::decode_json(<<EOT));
{
  "queryType" : "topN",
  "dataSource" : "metrics",
  "intervals" : ["$ts/PT1S"],
  "granularity" : "all",
  "dimension" : "page",
  "metric" : "value_sum",
  "threshold" : 25,
  "aggregations" : [
    {
      "type" : "doubleSum",
      "name" : "value_sum",
      "fieldName" : "value_sum"
    }
  ]
}
EOT
my $druid_expected = [{
  'result' => [
    {'page' => '/get/68', 'value_sum' => 61},
    {'page' => '/list', 'value_sum' => 60},
    {'page' => '/', 'value_sum' => 1},
  ],
  'timestamp' => $ts
}];

eq_or_diff($druid_result, $druid_expected, 'example druid query results are as expected');

# Pivot home page
my $pivot_result = $iap->get_pivot_config(1);
my @datasources = sort map { $_->{name} } @{$pivot_result->{'dataSources'}};
eq_or_diff(\@datasources, ['metrics'], 'example pivot config includes metrics datasource');

# PlyQL query
# $next_ts is a workaround for https://github.com/implydata/plyql/issues/2
my $next_ts = $ts;
$next_ts =~ s/\.000Z/\.001Z/;
my $plyql_result = $iap->post_bard("/plyql", {
  query => "SELECT page, SUM(value_sum) AS Value FROM metrics WHERE '$ts' <= time AND time < '$next_ts' GROUP BY page ORDER BY Value DESC LIMIT 5",
  outputType => 'json'
});
my $plyql_expected = [
    {'page' => '/get/68', 'Value' => 61},
    {'page' => '/list', 'Value' => 60},
    {'page' => '/', 'Value' => 1},
];

eq_or_diff($plyql_result, $plyql_expected, 'example plyql query results are as expected');
