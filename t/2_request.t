#!/usr/bin/env perl

use strict;
use Test::More;
use HTTP::Response;
use HTTP::Request;
use Digest::MD5;
use LWP::UserAgent::Cached;

eval {
	require File::Temp;
	File::Temp->import('tempdir');
};
if ($@) {
	plan skip_all => 'File::Temp not installed';
}

eval {
	require Test::Mock::LWP::Dispatch;
};
if ($@) {
	plan skip_all => 'Test::Mock::LWP::Dispatch not installed';
}

my $cache_dir = eval {
	tempdir(CLEANUP => 1)
};


unless ($cache_dir) {
	plan skip_all => "Сan't create temp dir";
}

my $ua = LWP::UserAgent::Cached->new(cache_dir => $cache_dir, cookie_jar => {});

# simple request test
my $mid = $ua->map('http://www.google.com/', HTTP::Response->new(200));
$ua->get('http://www.google.com/'); # cache 200 OK
$ua->unmap($mid);
$ua->map('http://www.google.com/', HTTP::Response->new(500));
is($ua->get('http://www.google.com/')->code, 200, 'Cached 200 ok response');

# more complex request test
my $response = HTTP::Response->new(301, 'Moved Permanently', [Location => 'http://www.yahoo.com/']);
$response->request(HTTP::Request->new(GET => 'http://yahoo.com'));
$mid = $ua->map('http://yahoo.com', $response);
my $y_mid = $ua->map('http://www.yahoo.com/', HTTP::Response->new(200, 'Ok', ['Set-Cookie' => 'lwp=true; cached=yes'], 'This is a test'));
$ua->get('http://yahoo.com'); # make cache
$ua->unmap($mid);
$ua->cookie_jar->clear();
my $resp = $ua->get('http://yahoo.com');
is($resp->code, 200, 'Cached response with redirect');
ok(index($resp->content, 'This is a test')!=-1, 'Cached response content') or diag "Content: ", $resp->content;
ok($ua->cookie_jar->as_string =~ /^(?=.*?lwp=true).*?cached=yes/, 'Cookies from the cache') or diag "Cookies: ", $ua->cookie_jar->as_string;

# nocache test
$ua->nocache(sub {
	$_[0]->code > 399
});
$mid = $ua->map('http://perl.org', HTTP::Response->new(403, 'Forbbidden'));
$ua->get('http://perl.org');
$ua->unmap($mid);
$ua->map('http://perl.org', HTTP::Response->new(200, 'OK', [], 'Perl there'));
$resp = $ua->get('http://perl.org');
is($resp->code, 200, 'Nocache code');
ok(index($resp->content, 'Perl there')!=-1, 'Nocache content') or diag 'Content: ', $resp->content;
$ua->nocache(undef);

# recache test
$ua->recache(sub {
	my ($resp, $path) = @_;
	isa_ok($resp, 'HTTP::Response');
	ok(-e $path, 'Cached file exists') or diag "Path: $path";
	1;
});
$mid = $ua->map('http://perlmonks.org', HTTP::Response->new(407));
$ua->get('http://perlmonks.org');
$ua->unmap($mid);
$ua->map('http://perlmonks.org', HTTP::Response->new(200));
is($ua->get('http://perlmonks.org')->code, 200, 'Recached');
$ua->recache(undef);

# uncache test
$mid = $ua->map('http://metacpan.org', HTTP::Response->new(200));
$ua->get('http://metacpan.org');
$ua->uncache();
$ua->unmap($mid);
$ua->map('http://metacpan.org', HTTP::Response->new(503));
is($ua->get('http://metacpan.org')->code, 503, 'Uncache last response');

#collision test
$ua->cookie_jar->clear();
$resp = $ua->get('http://yahoo.com');
$ua->cookie_jar->clear();
my $hash = Digest::MD5::md5_hex( $resp->request->as_string );
open FH, '>:raw', "$cache_dir/$hash";
print FH "http://google.com\nHTTP/1.1 200 OK\n";
close FH;
$ua->get('http://yahoo.com');
ok(-e "$cache_dir/$hash-001", "Collision detected");

open FH, '>:raw', "$cache_dir/$hash-001";
print FH "http://google.com\nHTTP/1.1 200 OK\n";
close FH;
$ua->cookie_jar->clear();
$ua->get('http://yahoo.com');
ok(-e "$cache_dir/$hash-001", "Double collision detected");

$ua->unmap($y_mid);
$ua->map('http://www.yahoo.com/', HTTP::Response->new(404));
is($ua->get('http://yahoo.com')->code, 200, 'Cached response (collision list)');

done_testing;
