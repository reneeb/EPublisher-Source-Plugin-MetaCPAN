package EPublisher::Source::Plugin::MetaCPAN;

use strict;
use warnings;

use File::Basename;
use MetaCPAN::API;

use EPublisher::Source::Base;
use EPublisher::Utils::PPI qw(extract_pod_from_code);

our @ISA = qw( EPublisher::Source::Base );

our $VERSION = 0.11;

# implementing the interface to EPublisher::Source::Base
sub load_source{
    my ($self) = @_;

    my $options = $self->_config;
    
    return '' unless $options->{module};

    my $module = $options->{module};    # the name of the CPAN-module
    my $mcpan  = MetaCPAN::API->new;

    # fetching the requested module from metacpan
    my $module_result = $mcpan->fetch( 'release/' . $module );

    # this produces something like e.g. "EPublisher-0.6"
    my $release  = sprintf "%s-%s", $module, $module_result->{version};

    # get the manifest with module-author and modulename-moduleversion
    my $manifest = $mcpan->source(
        author  => $module_result->{author},
        release => $release,
        path    => 'MANIFEST',
    );

    # make a list from all possible POD-files in the lib directory
    my @files     = split /\n/, $manifest;
    # some MANIFESTS (like POD::Parser) have comments after the filenames,
    # so we match against an optional \s instead of \z
    # the manifest, in POD::Parser in looks e.g. like this:
    #
    # lib/Pod/Usage.pm     -- The Pod::Usage module source
    # lib/Pod/Checker.pm   -- The Pod::Checker module source
    # lib/Pod/Find.pm      -- The Pod::Find module source
    my @pod_files = grep{ /^.*\.p(?:od|m)\s?/  # all POD everywhere
                          and not
                          /^(?:example\/|t\/)/ # but not in example/ or t/
                        }@files;

    # here whe store POD if we find some later on
    my @pod;

    # look for POD
    for my $file ( @pod_files ) {

        # we match the filename again, in case there are comments in
        # the manifest, in POD::Parser in looks e.g. like this:
        #
        # lib/Pod/Usage.pm     -- The Pod::Usage module source
        # lib/Pod/Checker.pm   -- The Pod::Checker module source
        # lib/Pod/Find.pm      -- The Pod::Find module source
        if ( $file =~ m/^(.*\.p(?:od|m))\s/) {
            # throw away any comments!
            $file = $1;
        }

        # the call below ($mcpan->pod()) fails if there is no POD in a
        # module so this is why I filter all the modules. I check if they
        # have any line BEGINNING with '=head1' ore similar
        my $source = $mcpan->source(
            author         => $module_result->{author},
            release        => $release,
            path           => $file,
        );
        # The Moose-Project made me write this filtering Regex, because
        # they have .pm's without POD, and also with nonsense POD which
        # still fails if you call $mcpan->pod
        my $pod_src;
        if ($source =~ /\n=(HEAD|Head|head)\d+/) {
            $pod_src = $mcpan->pod(
                author         => $module_result->{author},
                release        => $release,
                path           => $file,
                'content-type' => 'text/x-pod',
            );

            next if $pod_src eq '{}';
        }
        else {
            # if there is no head we consider this POD unvalid
            next;
        }
        
        # check if $result is always only the Pod
        #push @pod, extract_pod_from_code( $result );
        my $filename = basename $file;
        my $title    = $file;

        $title =~ s{lib/}{};
        $title =~ s{\.p(?:m|od)\z}{};
        $title =~ s{/}{::}g;
 
        push @pod, { pod => $pod_src, filename => $filename, title => $title };
    }
    
    # voilà
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

=cut
