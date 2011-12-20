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
	my $self = $class->SUPER::new(%opts);
	$self->{cache_dir} = $cache_dir;
	
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

sub simple_request {
	my $self = shift;
	unless (defined $self->{cache_dir}) {
		return $self->SUPER::simple_request(@_);
	}
	
	my ($request, $content_handler, $read_size_hint) = @_;
	my $fpath = $self->{cache_dir} . '/' . Digest::MD5::md5_hex($request->as_string);
	my $response;
	
	if (-e $fpath) {
		if (open my $fh, $fpath) {
			local $/ = undef;
			my $response_str = <$fh>;
			close $fh;
			$response = HTTP::Response->parse($response_str);
			$response->request( $self->prepare_request($request) );
		}
		else {
			carp "open('$fpath', 'r'): $!";
		}
	}
	
	unless ($response) {
		$response = $self->SUPER::simple_request(@_);
		if (open my $fh, '>', $fpath) {
			print $fh $response->as_string;
			close $fh;
		}
		else {
			carp "open('$fpath', 'w'): $!";
		}
	}
	
	return $response;
}

1;
