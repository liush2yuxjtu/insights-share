#!/usr/bin/env bash
# inject-insights.sh — UserPromptSubmit hook (B-architecture).
#
# Per design doc:
#   - Hot-path = local cache only, no git fetch, ≤500ms p95.
#   - Background: cold-start (mirror clone discovery) + buffer-recover.
#
# Keep the hot path in one lightweight process. Python and full JSON module
# startup can exceed the 500ms p95 budget on busy machines, so this path uses
# a best-effort no-module Perl parser over the narrow hook/cache shapes.

set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
export PLUGIN_ROOT
export INSIGHTS_ROOT="${INSIGHTS_ROOT:-$HOME/.gstack/insights}"
export INSIGHTS_RETRIEVAL_TOP_K="${INSIGHTS_RETRIEVAL_TOP_K:-3}"

exec perl -we '
use strict;
use warnings;

my $raw = do { local $/; <STDIN> // "" };

sub unescape_json_string {
  my ($s) = @_;
  $s =~ s/\\n/\n/g;
  $s =~ s/\\r/\r/g;
  $s =~ s/\\t/\t/g;
  $s =~ s/\\"/"/g;
  $s =~ s/\\\\/\\/g;
  return $s;
}

sub json_string_value {
  my ($text, $key) = @_;
  return unescape_json_string($1) if $text =~ /"\Q$key\E"\s*:\s*"((?:\\.|[^"\\])*)"/s;
  return "";
}

my $prompt = json_string_value($raw, "prompt");
$prompt =~ s/^\s+|\s+$//g;
exit 0 if $prompt eq "";

my $cwd = json_string_value($raw, "cwd") || $ENV{PWD} || ".";
my $root = $ENV{INSIGHTS_ROOT} || "$ENV{HOME}/.gstack/insights";
my $top_k = int($ENV{INSIGHTS_RETRIEVAL_TOP_K} || 3);

sub abs_path {
  my ($path) = @_;
  return $path if $path =~ m{^/};
  my $base = $ENV{PWD} || ".";
  return "$base/$path";
}

sub dirname_of {
  my ($path) = @_;
  $path =~ s{/+$}{};
  $path =~ s{/[^/]+$}{};
  return $path || "/";
}

sub git_config_for {
  my ($dir) = @_;
  return "" if !$dir || !-d $dir;
  my $cur = abs_path($dir);
  while (1) {
    my $git = "$cur/.git";
    if (-d $git && -f "$git/config") {
      return "$git/config";
    }
    if (-f $git) {
      if (open my $fh, "<", $git) {
        my $line = <$fh> // "";
        close $fh;
        if ($line =~ /^gitdir:\s*(.+?)\s*$/) {
          my $gd = $1;
          $gd = "$cur/$gd" unless $gd =~ m{^/};
          return "$gd/config" if -f "$gd/config";
        }
      }
    }
    my $parent = dirname_of($cur);
    last if $parent eq $cur;
    $cur = $parent;
  }
  return "";
}

sub canonical_slug {
  my ($dir) = @_;
  my $config = git_config_for($dir);
  return "" if !$config;
  open my $fh, "<", $config or return "";
  my ($in_origin, $url) = (0, "");
  while (my $line = <$fh>) {
    if ($line =~ /^\s*\[remote\s+"origin"\]\s*$/) {
      $in_origin = 1;
      next;
    }
    if ($line =~ /^\s*\[/) {
      $in_origin = 0;
      next;
    }
    if ($in_origin && $line =~ /^\s*url\s*=\s*(.+?)\s*$/) {
      $url = $1;
      last;
    }
  }
  close $fh;
  return "" if $url eq "";
  my ($host, $path);
  if ($url =~ /^git@([^:]+):(.+)$/) {
    ($host, $path) = ($1, $2);
  } elsif ($url =~ /^(?:ssh|https?):\/\/(?:[^@]+@)?([^\/]+)\/(.+)$/) {
    ($host, $path) = ($1, $2);
  } else {
    return "";
  }
  $host = lc($host);
  $host =~ s/:(?:22|443)$//;
  $path = lc($path);
  $path =~ s/\/$//;
  $path =~ s/\.git$//;
  $path =~ s/\//__/g;
  return "${host}__${path}";
}

sub load_lessons {
  my ($slug) = @_;
  return () if $slug eq "";
  my @files = (
    "$root/$slug/.mirror/lessons.jsonl",
    "$root/$slug/lessons.jsonl",
  );
  my (%seen, @lessons);
  for my $file (@files) {
    next if !-f $file;
    open my $fh, "<", $file or next;
    while (my $line = <$fh>) {
      $line =~ s/^\s+|\s+$//g;
      next if $line eq "";
      my $id = json_string_value($line, "id");
      next if $id ne "" && $seen{$id}++;
      my $text = json_string_value($line, "text");
      my @tags = ();
      if ($line =~ /"topic_tags"\s*:\s*\[(.*?)\]/s) {
        my $tag_src = $1;
        while ($tag_src =~ /"((?:\\.|[^"\\])*)"/g) {
          push @tags, unescape_json_string($1);
        }
      }
      push @lessons, { id => $id, text => $text, topic_tags => \@tags };
    }
    close $fh;
  }
  return @lessons;
}

sub tokens {
  my ($text) = @_;
  my %out;
  for my $t (lc($text || "") =~ /[a-z0-9]{4,}/g) {
    $out{$t} = 1;
  }
  return \%out;
}

my $slug = canonical_slug($cwd);
exit 0 if $slug eq "";
my @lessons = load_lessons($slug);
exit 0 if !@lessons;

my $prompt_tokens = tokens($prompt);
exit 0 if !%$prompt_tokens;

my @scored;
for my $lesson (@lessons) {
  my @tags = map { lc($_) } @{ $lesson->{topic_tags} };
  my $text_tokens = tokens($lesson->{text});
  my $tag_hits = 0;
  for my $tag (@tags) {
    for my $pt (keys %$prompt_tokens) {
      $tag_hits++ if index($tag, $pt) >= 0 || index($pt, $tag) >= 0;
    }
  }
  my $bag = 0;
  for my $pt (keys %$prompt_tokens) {
    $bag++ if $text_tokens->{$pt};
  }
  my $score = 3 * $tag_hits + $bag;
  push @scored, [$score, $lesson] if $score > 0;
}
exit 0 if !@scored;

@scored = sort { $b->[0] <=> $a->[0] } @scored;
splice(@scored, $top_k) if @scored > $top_k;

print "\n<insights-share>\n";
print "The following " . scalar(@scored) . " team insight(s) appear relevant to this prompt. ";
print "Treat them as prior good/bad examples (no `solution` tag - choose what fits this context). ";
print "Cite the lesson_id when you act on one.\n\n";

my $i = 1;
for my $hit (@scored) {
  my ($score, $lesson) = @$hit;
  my $id = $lesson->{id} || "unknown";
  my $tags = join(",", @{ $lesson->{topic_tags} });
  my $text = $lesson->{text} || "";
  $text =~ s/^\s+|\s+$//g;
  $text = substr($text, 0, 600) . " ..." if length($text) > 600;
  print "[$i] lesson_id=$id  tags=$tags  score=$score\n";
  my @lines = split /\n/, $text;
  @lines = ($text) if !@lines;
  for my $line (@lines) {
    print "    $line\n";
  }
  print "\n";
  $i++;
}
print "</insights-share>\n";
'
