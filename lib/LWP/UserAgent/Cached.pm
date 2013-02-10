package LWP::UserAgent::Cached;

use strict;
use Carp;
use Digest::MD5;
use HTTP::Response;
use base 'LWP::UserAgent';

our $VERSION = '0.04';

sub new {
	my ($class, %opts) = @_;
	
	my $cache_dir      = delete $opts{cache_dir};
	my $nocache_if     = delete $opts{nocache_if};
	my $recache_if     = delete $opts{recache_if};
	my $on_uncached    = delete $opts{on_uncached};
	my $cachename_spec = delete $opts{cachename_spec};
	my $self = $class->SUPER::new(%opts);
	
	$self->{cache_dir}      = $cache_dir;
	$self->{nocache_if}     = $nocache_if;
	$self->{recache_if}     = $recache_if;
	$self->{on_uncached}    = $on_uncached;
	$self->{cachename_spec} = $cachename_spec;
	
	return $self;
}

# generate getters and setters
foreach my $opt_name (qw(cache_dir nocache_if recache_if on_uncached cachename_spec)) {
	no strict 'refs';
	*$opt_name = sub {
		my $self = shift;
		if (@_) {
			my $opt_val = $self->{$opt_name};
			$self->{$opt_name} = shift;
			return $opt_val;
		}
		
		return $self->{$opt_name};
	}
}

sub simple_request {
	my $self = shift;
	unless (defined $self->{cache_dir}) {
		return $self->SUPER::simple_request(@_);
	}
	
	my $request = $_[0];
	eval{ $self->prepare_request($request) };
	my $fpath = $self->_get_cache_name($request);
	my $response;
	my $no_collision_suffix;
	
	if (-e $fpath) {
		unless ($response = $self->_parse_cached_response($fpath, $request)) {
			# collision
			if (my @cache_list = <$fpath-*>) {
				foreach my $cache_file (@cache_list) {
					if ($response = $self->_parse_cached_response($cache_file, $request)) {
						$fpath = $cache_file;
						last;
					}
				}
				
				unless ($response) {
					$no_collision_suffix = sprintf('-%03d', substr($cache_list[-1], -3) + 1);
				}
			}
			else {
				$no_collision_suffix = '-001';
			}
		}
		
		if ($response && defined($self->{recache_if}) && $self->{recache_if}->($response, $fpath)) {
			$response = undef;
		}
	}
	
	unless ($response) {
		if (defined $self->{on_uncached}) {
			$self->{on_uncached}->($request);
		}
		
		$response = $self->SUPER::simple_request(@_);
		
		if (!defined($self->{nocache_if}) || !$self->{nocache_if}->($response)) {
			if (defined $no_collision_suffix) {
				$fpath .= $no_collision_suffix;
			}
			
			if (open my $fh, '>:raw', $fpath) {
				print $fh $request->url, "\n";
				print $fh $response->as_string;
				close $fh;
				
				unless ($self->{was_redirect}) {
					@{$self->{last_cached}} = ();
				}
				push @{$self->{last_cached}}, $fpath;
				$self->{was_redirect} = $response->is_redirect && _in($request->method, $self->requests_redirectable);
			}
			else {
				carp "open('$fpath', 'w'): $!";
			}
		}
	}
	
	return $response;
}

sub last_cached {
	my $self = shift;
	return exists $self->{last_cached} ?
		@{$self->{last_cached}} : ();
}

sub uncache {
	my $self = shift;
	unlink $_ for $self->last_cached;
}

sub _get_cache_name {
	my ($self, $request) = @_;
	
	if (defined($self->{cachename_spec}) && %{$self->{cachename_spec}}) {
		my $tmp_request = $request->clone();
		my $leave_only_specified;
		if (exists $self->{cachename_spec}{_headers}) {
			ref $self->{cachename_spec}{_headers} eq 'ARRAY'
				or croak 'cachename_spec->{_headers} should be array ref';
			$leave_only_specified = 1;
		}
		
		foreach my $hname ($tmp_request->headers->header_field_names) {
			if (exists $self->{cachename_spec}{$hname}) {
				if (defined $self->{cachename_spec}{$hname}) {
					$tmp_request->headers->header($hname, $self->{cachename_spec}{$hname});
				}
				else {
					$tmp_request->headers->remove_header($hname);
				}
			}
			elsif ($leave_only_specified && !_in($hname, $self->{cachename_spec}{_headers})) {
				$tmp_request->headers->remove_header($hname);
			}
		}
		
		if (exists $self->{cachename_spec}{_body}) {
			$tmp_request->content($self->{cachename_spec}{_body});
		}
		
		return $self->{cache_dir} . '/' . Digest::MD5::md5_hex($tmp_request->as_string);
	}
	
	return $self->{cache_dir} . '/' . Digest::MD5::md5_hex($request->as_string);
}

sub _parse_cached_response {
	my ($self, $cache_file, $request) = @_;
	
	my $fh;
	unless (open $fh, '<:raw', $cache_file) {
		carp "open('$cache_file', 'r'): $!";
		return;
	}
	
	my $url = <$fh>;
	$url =~ s/\s+$//;
	if ($url ne $request->url) {
		close $fh;
		return;
	}
	
	local $/ = undef;
	my $response_str = <$fh>;
	close $fh;
	
	my $response = HTTP::Response->parse($response_str);
	$response->request($request);
	
	if ($self->cookie_jar) {
		$self->cookie_jar->extract_cookies($response);
	}
	
	return $response;
}

sub _in($$) {
	my ($what, $where) = @_;
	
	foreach my $item (@$where) {
		return 1 if ($what eq $item);
	}
	
	return 0;
}

1;

=pod

=head1 NAME

LWP::UserAgent::Cached - LWP::UserAgent with simple caching mechanism

=head1 SYNOPSIS

    use LWP::UserAgent::Cached;
    
    my $ua = LWP::UserAgent::Cached->new(cache_dir => '/tmp/lwp-cache');
    my $resp = $ua->get('http://google.com/'); # makes http request
    
    ...
    
    $resp = $ua->get('http://google.com/'); # no http request - will get it from the cache

=head1 DESCRIPTION

When you process content from some website, you will get page one by one and extract some data from this
page with regexp, DOM parser or smth else. Sometimes we makes errors in our data extractors and realize this
only when all 1_000_000 pages were processed. We should fix our extraction logic and start all process from the
beginning. Please STOP! How about cache? Yes, you can cache all responses and second, third and other attempts will
be very fast.

LWP::UserAgent::Cached is yet another LWP::UserAgent subclass with cache support. It stores
cache in the files on local filesystem and if response already available in the cache returns it instead of making HTTP request.
This module was writed because other available alternatives didn't meet my needs:

=over

=item L<LWP::UserAgent::WithCache>

caches responses on local filesystem and gets it from the cache only if online document was not modified

=item L<LWP::UserAgent::Cache::Memcached>

same as above but stores cache in memory

=item L<LWP::UserAgent::Snapshot>

can record responses in the cache or get responses from the cache, but not both for one useragent

=item L<LWP::UserAgent::OfflineCache>

seems it may cache responses and get responses from the cache, but has too much dependencies and unclear
`delay' parameter

=back

=head1 METHODS

All LWP::UserAgent methods and few new.

=head2 new(...)

Creates new LWP::UserAgent::Cached object. Since LWP::UserAgent::Cached is LWP::UserAgent subclass it has all same
parameters, but in additional it has some new optional pararmeters:

cache_dir - Path to the directory where cache will be stored. If not set useragent will behaves as LWP::UserAgent without
cache support.

nocache_if - Reference to subroutine. First parameter of this subroutine will be HTTP::Response object. This subroutine
should return true if this response should not be cached and false otherwise. If not set all responses will be cached.

recache_if - Reference to subroutine. First parameter of this subroutine will be HTTP::Response object, second - path to
file with cache. This subroutine should return true if response needs to be recached (new HTTP request will be made)
and false otherwise. This subroutine will be called only if response already available in the cache.

on_uncached - Reference to subroutine. First parameter of this subroutine will be HTTP::Request object. This subroutine will
be called for each non-cached http request, before actually request.

cachename_spec - Hash reference to cache naming specification. In fact cache naming for each request based on request content.
Internally it is md5_hex($request->as_string). But what if some of request headers in your program changed dinamically, e.g.
User-Agent or Cookie? In such case caching will not work properly for you. We need some way to omit this headers when calculating
cache name. This option is what you need. Specification hash should contain header name and header value which will be used 
(instead of values in request) while calculating cache name.

For example we already have cache where 'User-Agent' value in the headers was 'Mozilla/5.0', but in the current version of the program 
it will be changed for each request. So we force specified that for cache name calculation 'User-Agent' should be 'Mozilla/5.0'. Cached
request had not 'Accept' header, but in the current version it has. So we force specified do not include this header for cache name
calculation.

    cachename_spec => {
        'User-Agent' => 'Mozilla/5.0',
        'Accept' => undef
    }

Specification hash may contain two special keys: '_body' and '_headers'. With '_body' key you can specify body content in the request
for cache name calculation. For example to not include body content in cache name calculation set '_body' to undef or empty string.
With '_headers' key you can specify which headers should be included in $request for cache name calculation. For example you can say to
include only 'Host' and 'Referer'. '_headers' value should be array reference:

    cachename_spec => {
        _body => undef, # omit body
        _headers => ['Host'], # include only host with value from request
        # It will be smth like:
        # md5_hex("METHOD url\r\nHost: host\r\n\r\n")
        # method and url will be included in any case
    }

Another example. Omit body, include only 'Host' and 'User-Agent' headers, use 'Host' value from request and specified 'User-Agent' value,
in addition include referrer with specified value ('Referer' not specified in '_headers', but values from main specification hash has
higher priority):

    cachename_spec => {
        _body => '',
        _headers => ['Host', 'User-Agent'],
        'User-Agent' => 'Mozilla/5.0',
        'Referer' => 'http://www.com'
    }

One more example. Calculate cache name based only on method and url:

    cachename_spec => {
        _body =>'',
        _headers => []
    }

LWP::UserAgent::Cached creation example:

    use LWP::UserAgent::Cached;
    
    my $ua = LWP::UserAgent::Cached->new(cache_dir => 'cache/lwp', nocache_if => sub {
        my $response = shift;
        return $response->code >= 500; # do not cache any bad response
    }, recache_if => sub {
        my ($response, $path) = @_;
        return $response->code == 404 && -M $path > 1; # recache any 404 response older than 1 day
    }, on_uncached => sub {
        my $request = shift;
        sleep 5 if $request->uri =~ '/category/\d+'; # delay before http requests inside "/category"
    }, cachename_spec => {
        'User-Agent' => undef, # omit agent while calculating cache name
    });

=head2 cache_dir() or cache_dir($dir)

Gets or sets corresponding option from the constructor.

=head2 nocache_if() or nocache_if($sub)

Gets or sets corresponding option from the constructor.

=head2 recache_if() or recache_if($sub)

Gets or sets corresponding option from the constructor.

=head2 on_uncached() or on_uncached($sub)

Gets or sets corresponding option from the constructor.

=head2 cachename_spec() or cachename_spec($spec)

Gets or sets corresponding option from the constructor.

=head2 last_cached()

Returns list with pathes to files with cache stored by last noncached response. List may contain more than one
element if there was redirect.

=head2 uncache()

Removes last response from the cache. Use case example:

    my $page = $ua->get($url)->decoded_content;
    if ($page =~ /Access for this ip was blocked/) {
        $ua->uncache();
    }

=head1 SEE ALSO

L<LWP::UserAgent>

=head1 COPYRIGHT

Copyright Oleg G <oleg@cpan.org>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
