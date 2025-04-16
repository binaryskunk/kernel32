#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;

use File::Copy;
use File::Path qw(make_path);

use POSIX qw(strftime);

use utf8;
use open qw(:std :utf8);

my $title = '';
my $date = '';
my $slug = '';
my $tags = '';
my $categories = '';

my $usage = "usage:\n\t$0 [-s/--slug post-slug] [-d/--date 2004/01/12] [-c/--categories 'category 1','category 2',...] [-t/--tags 'tag 1','tag 2',...] 'Post title'";

GetOptions(
  "slug|s=s" => \$slug,
  "date|d=s" => \$date,
  "categories|c=s" => \$categories,
  "tags|t=s" => \$tags
) or die "$usage\n";

$title = join(' ', @ARGV) or die "$usage\n";

if (!$slug) {
  $slug = generate_slug($title);
}

if (!$date) {
  $date = strftime("%Y-%m-%d", localtime);
} else {
  if ($date =~ m|^(\d{4})/(\d{1,2})/(\d{1,2})$|) {
    $date = sprintf("%04d-02d-%02d", $1, $2, $3);
  } else {
    die "date format should be year/month/day\n";
  }
}

my @categories_array = split(/,\s*/, $categories);
my $categories_string = format_array(@categories_array);

my @tags_array = split(/,\s*/, $tags);
my $tags_string = format_array(@tags_array);

my $dir_path = "content/post/$slug";
make_path($dir_path) or die "failed to create post dir: $!";

my $template_path = "templates/post.md";
my $output_path = "$dir_path/index.md";

open(my $template_fp, '<', $template_path) or die "could not open template file: $!";
open(my $output_fp, '>', $output_path) or die "could not create output file: $!";

while (my $line = <$template_fp>) {
  $line =~ s/POST_TITLE/$title/g;
  $line =~ s/POST_DATE/$date/g;
  $line =~ s/POST_SLUG/$slug/g;
  $line =~ s/POST_CATEGORIES/$categories_string/g;
  $line =~ s/POST_TAGS/$tags_string/g;

  print $output_fp $line;
}

close($template_fp);
close($output_fp);

print "created new post at $output_path\n";

sub generate_slug {
  my ($text) = @_;

  $text = lc($text);

  $text =~ s/ç/c/g;
  $text =~ s/[áàâã]/a/g;
  $text =~ s/[éèê]/e/g;
  $text =~ s/[íìî]/i/g;
  $text =~ s/[óòôõ]/o/g;
  $text =~ s/[úùû]/u/g;

  $text =~ s/[^\w\s]//g;
  $text =~ s/[^a-z0-9\s]//g;

  $text =~ s/\s+/-/g;

  $text =~ s/^-+|-+$//g;

  return $text;
}

sub format_array {
  my @array = @_;
  if (@array) {
    return join(', ', map { "\"$_\"" } @array);
  }

  return '';
}
