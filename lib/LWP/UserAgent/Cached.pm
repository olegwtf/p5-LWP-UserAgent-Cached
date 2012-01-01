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
		unless ($response = _parse_response($fpath, $request)) {
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
