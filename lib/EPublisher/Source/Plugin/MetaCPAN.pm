package EPublisher::Source::Plugin::MetaCPAN;

use strict;
use warnings;

use MetaCPAN::API;

use EPublisher::Source::Base;
use EPublisher::Utils::PPI qw(extract_pod_from_code);

our @ISA = qw( EPublisher::Source::Base );

our $VERSION = 0.01;

sub load_source{
    my ($self, $options) = @_;
    
    return '' unless $options->{module};

    my $module = $options->{module};
    my $mcpan  = MetaCPAN::API->new;

    my $module_result = $mcpan->fetch( '/release/' . $module );

    my $release  = sprintf "%s-%s", $module, $module_result->{version};
    my $manifest = $mcpan->source(
        author  => $module_result->{author},
        release => $release,
        path    => 'MANIFEST',
    );

    my @files     = split /\n/, $manifest;
    my @pod_files = grep{ /\.p(?:od|m)\z/ }@files;
    my @pod;

    for my $file ( @pod_files ) {

        my $result = $mcpan->pod(
            author         => $module_result->{author},
            release        => $release,
            path           => $file,
            'content-type' => 'text/x-pod',
        );

        next if $result eq '{}';
        
        # check if $result is always only the Pod
        #push @pod, extract_pod_from_code( $result );
        push @pod, $result;
    }
    
    return @pod;
}

1;

=head1 NAME

EPublisher::Source::Plugin::MetaCPAN - MetaCPAN source plugin

=head1 SYNOPSIS

  my $source_options = { type => 'MetaCPAN', module => 'Moose' };
  my $url_source     = EPublisher::Source->new( $source_options );
  my $pod            = $url_source->load_source;

=head1 METHODS

=head2 load_source

  $url_source->load_source;

reads the URL 

=head1 COPYRIGHT & LICENSE

Copyright 2011 Renee Baecker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of Artistic License 2.0.

=head1 AUTHOR

Renee Baecker (E<lt>module@renee-baecker.deE<gt>)

=cut