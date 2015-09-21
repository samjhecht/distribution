package ImplyTest;

use strict;
use warnings;

use Carp;
use Exporter qw/import/;
use File::Spec;
use File::Temp;
use IPC::Run;
use JSON ();

our @EXPORT = qw/retry/;

sub new
{
  my ($self, %args) = @_;
  my $tarball = $ENV{TARBALL};
  my $tmpdir = File::Temp::tempdir("iap-test-dir-XXXXX", CLEANUP => 1);
  system("tar", "-C", $tmpdir, "-xzf", $tarball) == 0
    or die "unpacking failed: $tarball";
  my @contents = glob "$tmpdir/imply-*";
  die "no imply- dir?" if @contents != 1;
  my $implydir = File::Spec->rel2abs($contents[0]);

  if ($args{vardir}) {
    symlink($args{vardir}, "$implydir/var") or die "symlink $implydir/var -> $args{vardir} failed: $!\n";
  }

  # Speed up coordinator a bit so the tests run faster.
  system(
    '/usr/bin/env',
    'perl', '-pi', '-e',
    's/druid.coordinator.period=.*/druid.coordinator.period=PT1S/g',
    "$implydir/conf/druid/coordinator/runtime.properties"
  ) == 0 or die;

  return bless {
    tmpdir => $tmpdir,
    dir => $implydir,
  }, $self;
}

sub start
{
  my ($self, $conf) = @_;

  if ($self->{supervise}) {
    die "already started";
  }

  my $supervise_cmd = [
    "$self->{dir}/bin/supervise",
    "-c", "$self->{dir}/conf/supervise/$conf.conf",
    "-t", "1"
  ];

  $self->{supervise} = IPC::Run::start($supervise_cmd, '<', '/dev/null', '>>', '/dev/null', '2>>', '/dev/null')
    or die "start failed";

  1;
}

sub dir
{
  my ($self) = @_;
  return $self->{dir};
}

sub runtask
{
  my ($self, $index_object) = @_;
  my $index_json = JSON::encode_json($index_object);
  my ($index_fh, $index_file) = File::Temp::tempfile(UNLINK => 1, TEMPLATE => "iap-test-task-XXXXX");
  print $index_fh $index_json;
  close $index_fh;

  $self->backtick([
    "bin/post-index-task",
    '-f', File::Spec->rel2abs($index_file),
    '-u', 'http://localhost:8084/'
  ]);

  1;
}

sub await_load
{
  my ($self, $datasource) = @_;

  return retry(sub {
    my $rsp = JSON::decode_json($self->backtick([
      "curl",
      "-f",
      "-L",
      "http://localhost:8081/druid/coordinator/v1/loadstatus"
    ]));
    if (!$rsp->{$datasource} || $rsp->{$datasource} != 100) {
      die "response was " . JSON::encode_json($rsp);
    } else {
      return $rsp->{$datasource};
    }
  }, tries => 150);
}

sub query_druid
{
  my ($self, $query_object) = @_;
  my $query_json = JSON::encode_json($query_object);
  my ($query_fh, $query_file) = File::Temp::tempfile(UNLINK => 1, TEMPLATE => "iap-test-query-XXXXX");
  print $query_fh $query_json;
  close $query_fh;

  my $rsp = JSON::decode_json($self->backtick([
    "curl",
    "-f",
    "-L",
    "-HContent-Type: application/json",
    "-XPOST",
    "--data-binary", '@' . File::Spec->rel2abs($query_file),
    "http://localhost:8082/druid/v2"
  ]));
  if (@$rsp) {
    return $rsp;
  } else {
    die "no results returned";
  }
}

sub get_pivot_config
{
  my ($self, $expected_num_datasources) = @_;
  return retry(sub {
    my $rsp = $self->backtick([
      "curl",
      "-f",
      "-L",
      "http://localhost:9095/pivot"
    ]);
    if ($rsp =~ m!var PIVOT_CONFIG = (.*);</script>!) {
      my $obj = JSON::decode_json($1);
      if (@{$obj->{dataSources}} >= $expected_num_datasources) {
        return $obj;
      } else {
        die "not enough dataSources";
      }
    } else {
      die "can't find PIVOT_CONFIG";
    }
  }, tries => 15);
}

sub post_bard
{
  my ($self, $path, $query_object) = @_;
  my $query_json = JSON::encode_json($query_object);
  my ($query_fh, $query_file) = File::Temp::tempfile(UNLINK => 1, TEMPLATE => "iap-test-query-XXXXX");
  print $query_fh $query_json;
  close $query_fh;

  return retry(sub {
    my $rsp = JSON::decode_json($self->backtick([
      "curl",
      "-f",
      "-L",
      "-HContent-Type: application/json",
      "-XPOST",
      "--data-binary", '@' . File::Spec->rel2abs($query_file),
      "http://localhost:9095$path"
    ]));
    if (@$rsp) {
      return $rsp;
    } else {
      die "no results returned";
    }
  }, tries => 15);
}

sub down
{
  my ($self) = @_;

  my $ret;
  if ($self->{supervise}) {
    $self->backtick(['bin/service', '--down']);
    $ret = $self->{supervise}->finish;
    $self->{supervise} = undef;
  }

  $ret;
}

sub term
{
  my ($self) = @_;

  my $ret;
  if ($self->{supervise}) {
    $self->{supervise}->signal('TERM');
    $ret = $self->{supervise}->finish;
    $self->{supervise} = undef;
  }

  $ret;
}

sub backtick
{
  my ($self, $command) = @_;

  if (ref $command eq 'ARRAY') {
    $command = join ' ', map { quotemeta $_ } @$command;
  }

  my $out = qx[cd \Q$self->{dir}\E && $command 2>/dev/null];
  if ($?) {
    die "command failed: $command: $? (out = $out)";
  } else {
    return $out;
  }
}

sub DESTROY
{
  my ($self) = @_;
  if ($self->{supervise}) {
    $self->term;
  }
}

sub retry {
  my ($coderef, %args) = @_;
  my $tries = $args{tries} || 1;

  while (1) {
    my $result;
    eval {
      $result = $coderef->();
    };
    if ($@) {
      $tries --;
      if ($tries <= 0) {
        croak "retries exhausted; last error was: $@";
      } else {
        sleep 1;
      }
    } else {
      return $result;
    }
  }
}

1;
