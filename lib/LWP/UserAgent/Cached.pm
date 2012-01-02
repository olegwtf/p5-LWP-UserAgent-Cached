package LWP::UserAgent::Cached;

use strict;
use Carp;
use Digest::MD5;
use HTTP::Response;
use base 'LWP::UserAgent';

our $VERSION = '0.01';

sub new {
	my ($class, %opts) = @_;
	
	my $cache_dir = delete $opts{cache_dir};
	my $nocache   = delete $opts{nocache};
	my $self = $class->SUPER::new(%opts);
	
	$self->{cache_dir} = $cache_dir;
	$self->{nocache}   = $nocache;
	
	return $self;
}

sub cache_dir {
	my $self = shift;
	if (@_) {
		my $cache_dir = $self->{cache_dir};
		$self->{cache_dir} = shift;
		return $cache_dir;
	}
	
	return $self->{cache_dir};
}

sub nocache {
	my $self = shift;
	if (@_) {
		my $nocache = $self->{nocache};
		$self->{nocache} = shift;
		return $nocache;
	}
	
	return $self->{nocache};
}

sub simple_request {
	my $self = shift;
	unless (defined $self->{cache_dir}) {
		return $self->SUPER::simple_request(@_);
	}
	
	my $request = $_[0];
	eval{ $self->prepare_request($request) };
	my $fpath = $self->{cache_dir} . '/' . Digest::MD5::md5_hex($request->as_string);
	my $response;
	my $no_collision_suffix;
	
	if (-e $fpath) {
		unless ($response = $self->_parse_cached_response($fpath, $request)) {
			# collision
			if (my @cache_list = <$fpath-*>) {
				foreach my $cache_file (@cache_list) {
					if ($response = $self->_parse_cached_response($cache_file, $request)) {
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
	}
	
	unless ($response) {
		$response = $self->SUPER::simple_request(@_);
		
		if (!defined($self->{nocache}) || ref($self->{nocache}) ne 'CODE' || !$self->{nocache}->($response)) {
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

sub uncache {
	my $self = shift;
	if (exists $self->{last_cached}) {
		unlink $_ for @{$self->{last_cached}};
	}
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
begin. Please STOP! How about cache? Yes, you can cache all responses and second, third and other attempts will
be very fast.

LWP::UserAgent::Cached is yet another LWP::UserAgent subclass with cache support. It stores
cache in the files on local filesystem and if response already available in the cache returns it instead of making HTTP response.
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

=head2 new(cache_dir => ..., nocache => ..., ...)

Creates new LWP::UserAgent::Cached object. Since LWP::UserAgent::Cached is LWP::UserAgent subclass it has all same
parameters, but in additional it has some new optional pararmeters:

cache_dir - Path to the directory where cache will be stored. If not set useragent will behaves as LWP::UserAgent without
cache support.

nocache - Reference to subroutine. First parameter of this subroutine will be HTTP::Response object. This subroutine
should return true if this response should not be cached and false otherwise. If not set all responses will be cached.

Example:

    use LWP::UserAgent::Cached;
    
    my $ua = LWP::UserAgent::Cached->new(cache_dir => 'cache/lwp', nocache => sub {
        my $response = shift;
        return $response->code >= 400; # do not cache any bad response
    });

=head2 cache_dir() or cache_dir($dir)

Gets or sets corresponding option from the constructor.

=head2 nocache() or nocache($sub)

Gets or sets corresponding option from the constructor.

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
