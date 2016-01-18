#!/usr/bin/env perl

use strict;
use warnings;

use File::Temp qw/tempfile/;
use ImplyTest;
use JSON;
use Test::Differences;
use Test::More tests => 12;

my $iap = ImplyTest->new;
my $dir = $iap->dir;

# Start up services
ok($iap->start('quickstart'), 'started');

{
# Load example data
my $taskok = $iap->runtask(JSON::decode_json(scalar qx[cat \Q$dir\E/quickstart/wikiticker-index.json]));
ok($taskok, 'example index task');

# Wait for data to load
is($iap->await_load('wikiticker'), 100, 'example loading complete');

# Direct Druid query
my $druid_result = $iap->query_druid(JSON::decode_json(scalar qx[cat $dir/quickstart/wikiticker-top-pages.json]));
my $druid_expected = [{
  'result' => [
    {'page' => 'Wikipedia:Vandalismusmeldung', 'edits' => 33},
    {'page' => 'User:Cyde/List of candidates for speedy deletion/Subpage','edits' => 28},
    {'page' => 'Jeremy Corbyn','edits' => 27},
    {'edits' => 21,'page' => 'Wikipedia:Administrators\' noticeboard/Incidents'},
    {'edits' => 20,'page' => 'Flavia Pennetta'},
    {'edits' => 18,'page' => 'Total Drama Presents: The Ridonculous Race'},
    {'edits' => 18,'page' => 'User talk:Dudeperson176123'},
    {'page' => "Wikip\x{e9}dia:Le Bistro/12 septembre 2015",'edits' => 18},
    {'edits' => 17,'page' => 'Wikipedia:In the news/Candidates'},
    {'page' => 'Wikipedia:Requests for page protection','edits' => 17},
    {'edits' => 16,'page' => 'Utente:Giulio Mainardi/Sandbox'},
    {'edits' => 16,'page' => 'Wikipedia:Administrator intervention against vandalism'},
    {'page' => 'Anthony Martial','edits' => 15},
    {'page' => 'Template talk:Connected contributor','edits' => 13},
    {'edits' => 12,'page' => 'Chronologie de la Lorraine'},
    {'page' => 'Wikipedia:Files for deletion/2015 September 12','edits' => 12},
    {'edits' => 12,'page' => "\x{413}\x{43e}\x{43c}\x{43e}\x{441}\x{435}\x{43a}\x{441}\x{443}\x{430}\x{43b}\x{44c}\x{43d}\x{44b}\x{439} \x{43e}\x{431}\x{440}\x{430}\x{437} \x{436}\x{438}\x{437}\x{43d}\x{438}"},
    {'edits' => 11,'page' => 'Constructive vote of no confidence'},
    {'edits' => 11,'page' => 'Homo naledi'},
    {'edits' => 11,'page' => 'Kim Davis (county clerk)'},
    {'page' => 'Vorlage:Revert-Statistik','edits' => 11},
    {'edits' => 11,'page' => "\x{41a}\x{43e}\x{43d}\x{441}\x{442}\x{438}\x{442}\x{443}\x{446}\x{438}\x{44f} \x{42f}\x{43f}\x{43e}\x{43d}\x{441}\x{43a}\x{43e}\x{439} \x{438}\x{43c}\x{43f}\x{435}\x{440}\x{438}\x{438}"},
    {'page' => 'The Naked Brothers Band (TV series)','edits' => 10},
    {'page' => 'User talk:Buster40004','edits' => 10},
    {'edits' => 10,'page' => 'User:Valmir144/sandbox'}
  ],
  'timestamp' => '2015-09-12T00:46:58.771Z'
}];

eq_or_diff($druid_result, $druid_expected, 'example druid query results are as expected');

# Pivot home page
my $pivot_result = $iap->get_pivot_config(1);
my @datasources = sort map { $_->{name} } @{$pivot_result->{'dataSources'}};
eq_or_diff(\@datasources, ['wikiticker'], 'example pivot config includes all datasources');

# PlyQL query
my $plyql_result = $iap->post_bard("/plyql", {
  query => "SELECT page, SUM(count) AS Edits FROM wikiticker WHERE '2015-09-12T00:00:00' <= time AND time < '2015-09-13T00:00:00' GROUP BY page ORDER BY Edits DESC LIMIT 5",
  outputType => 'json'
});
my $plyql_expected = [
  {"Edits" => 33, "page" => "Wikipedia:Vandalismusmeldung"},
  {"Edits" => 28, "page" => "User:Cyde/List of candidates for speedy deletion/Subpage"},
  {"Edits" => 27, "page" => "Jeremy Corbyn"},
  {"Edits" => 21, "page" => "Wikipedia:Administrators' noticeboard/Incidents"},
  {"Edits" => 20, "page" => "Flavia Pennetta"}
];

eq_or_diff($plyql_result, $plyql_expected, 'example plyql query results are as expected');

# Plywood query
my $plywood_query = JSON::decode_json(<<'EOT');
{
   "dataSource" : "wikiticker",
   "expression" : {
      "actions" : [
        {
          "action" : "apply",
          "expression" : {
             "actions" : [
                {
                   "action" : "filter",
                   "expression" : {
                      "actions" : [
                         {
                            "action" : "in",
                            "expression" : {
                               "op" : "literal",
                               "type" : "TIME_RANGE",
                               "value" : {
                                  "end" : "2015-09-12T23:59:59.200Z",
                                  "start" : "2015-09-09T23:59:59.200Z"
                               }
                            }
                         }
                      ],
                      "expression" : {"name":"time", "op":"ref"},
                      "op" : "chain"
                   }
                }
             ],
             "expression" : {"name":"main", "op":"ref"},
             "op" : "chain"
          },
          "name" : "main"
        },
        {
          "action" : "apply",
          "expression" : {
             "actions" : [{"action":"sum","expression":{"name":"count","op":"ref"}}],
             "expression" : {"name":"main","op":"ref"},
             "op" : "chain"
          },
          "name" : "count"
        }
      ],
      "expression" : {
         "op" : "literal",
         "type" : "DATASET",
         "value" : [{}]
      },
      "op" : "chain"
   }
}
EOT

my $plywood_result = $iap->post_bard("/plywood", $plywood_query);
my $plywood_expected = [
  {"count" => 39243}
];

eq_or_diff($plywood_result, $plywood_expected, 'example plywood query results are as expected');
}

#
# Your own data!
#

{
# Write pageviews data to a file
my ($datafh, $datafile) = tempfile(UNLINK => 1);
$datafile = File::Spec->rel2abs($datafile);
print $datafh <<'EOT';
{"time": "2015-09-01T00:00:00Z", "url": "/foo/bar", "user": "alice", "latencyMs": 32}
{"time": "2015-09-01T01:00:00Z", "url": "/", "user": "bob", "latencyMs": 11}
{"time": "2015-09-01T01:30:00Z", "url": "/foo/bar", "user": "bob", "latencyMs": 45}
EOT
close $datafh;

# Index task
my $task_object = JSON::decode_json(<<EOT);
{
  "type" : "index_hadoop",
  "spec" : {
    "ioConfig" : {
      "type" : "hadoop",
      "inputSpec" : {
        "type" : "static",
        "paths" : "$datafile"
      }
    },
    "dataSchema" : {
      "dataSource" : "pageviews",
      "granularitySpec" : {
        "type" : "uniform",
        "segmentGranularity" : "day",
        "queryGranularity" : "none",
        "intervals" : ["2015-09-01/2015-09-02"]
      },
      "parser" : {
        "type" : "string",
        "parseSpec" : {
          "format" : "json",
          "dimensionsSpec" : {
            "dimensions" : ["url", "user"]
          },
          "timestampSpec" : {
            "format" : "auto",
            "column" : "time"
          }
        }
      },
      "metricsSpec" : [
        {"name" : "views", "type" : "count"},
        {"name" : "latencyMs", "type" : "doubleSum", "fieldName" : "latencyMs"}
      ]
    },
    "tuningConfig" : {
      "type" : "hadoop",
      "partitionsSpec" : {
        "type" : "hashed",
        "targetPartitionSize" : 5000000
      },
      "jobProperties" : {}
    }
  }
}
EOT

# Load data!
my $taskok = $iap->runtask($task_object);
ok($taskok, 'example index task');

# Wait for data to load
is($iap->await_load('pageviews'), 100, 'pageviews loading complete');

# Direct Druid query
my $query_result = $iap->query_druid({
  queryType => 'timeseries',
  dataSource => 'pageviews',
  granularity => 'day',
  filter => {
    type => 'selector',
    dimension => 'user',
    value => 'bob',
  },
  aggregations => [
    {type => 'longSum', name => 'views', fieldName => 'views'},
  ],
  intervals => "2015-09-01/P1D",
});

my $expected_result = [{
  'timestamp' => '2015-09-01T00:00:00.000Z',
  'result' => {'views' => 2},
}];

eq_or_diff($query_result, $expected_result, 'pageviews druid query results are as expected');

# Pivot home page
my $pivot_result = $iap->get_pivot_config(2);
my @datasources = sort map { $_->{name} } @{$pivot_result->{'dataSources'}};
eq_or_diff(\@datasources, ['pageviews', 'wikiticker'], 'pageviews pivot config includes all datasources');

# PlyQL query
my $plyql_result = $iap->post_bard("/plyql", {
  query => "SELECT user, SUM(views) FROM pageviews WHERE '2015-09-01T00:00:00' <= time AND time < '2015-09-02T00:00:00' GROUP BY user ORDER BY user",
  outputType => 'json'
});
my $plyql_expected = [
  {"user" => "alice", "SUM_views" => 1},
  {"user" => "bob", "SUM_views" => 2},
];

eq_or_diff($plyql_result, $plyql_expected, 'pageviews plyql query results are as expected');
}
