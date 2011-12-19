package LWP::UserAgent::Cached;

use strict;
use Digest::MD5;
use HTTP::Response;
use base 'LWP::UserAgent';

sub new {
	my ($class, %opts) = @_;
	
	my $cache_dir = delete $opts{cache_dir};
	my $self = $class->SUPER::new(%opts);
	$self->{cache_dir} = $cache_dir;
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
	
	if (-e $fpath) {
		open my $fh, $fpath; # XXX error checking
		local $/ = undef;
		my $response_str = <$fh>;
		close $fh;
		my $response = HTTP::Response->parse($fpath);
		$response->request($request);
		return $response;
	}
	
	open my $fh, '>', $fpath; # XXX error checking
	my $response = $self->SUPER::simple_request(@_);
	print $fh $response->as_string;
	close $fh;
	return $response;
}

1;
