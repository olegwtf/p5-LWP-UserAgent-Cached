#!/usr/bin/env perl

use Test::More;
use strict;

use_ok('LWP::UserAgent::Cached');

my $ua = LWP::UserAgent::Cached->new();
ok(defined $ua, 'new ua');
isa_ok($ua, 'LWP::UserAgent::Cached');
isa_ok($ua, 'LWP::UserAgent');

$ua = LWP::UserAgent::Cached->new(cache_dir => '/tmp', nocache => sub{1});
is($ua->cache_dir, '/tmp', 'cache_dir param');
is(ref($ua->nocache), 'CODE', 'nocache is code');

$ua->cache_dir('/var/tmp');
is($ua->cache_dir, '/var/tmp', 'runtime change cache_dir param');

my $old_nocache = $ua->nocache;
$ua->nocache(sub{0});
isnt($old_nocache, $ua->nocache, 'runtime change nocache param');

done_testing;
