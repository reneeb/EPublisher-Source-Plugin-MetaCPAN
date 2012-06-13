package EPublisher::Source::Plugin::MetaCPAN;

# ABSTRACT: Get POD from distributions via MetaCPAN

use strict;
use warnings;

use Data::Dumper;
use Encode;
use File::Basename;
use MetaCPAN::API;

use EPublisher::Source::Base;
use EPublisher::Utils::PPI qw(extract_pod_from_code);

our @ISA = qw( EPublisher::Source::Base );

our $VERSION = 0.18;

# implementing the interface to EPublisher::Source::Base
sub load_source{
    my ($self) = @_;

    $self->publisher->debug( '100: start ' . __PACKAGE__ );

    my $options = $self->_config;
    
    return '' unless $options->{module};

    my $module = $options->{module};    # the name of the CPAN-module
    my $dont_merge_release = $options->{onlythis};
    my $mcpan  = MetaCPAN::API->new;

    # metacpan does not handle ".pm" in dist names
    my $release_name_metacpan = $module;
    $release_name_metacpan    =~ s/\.pm\z//;

    # fetching the requested module from metacpan
    $self->publisher->debug( "103: fetch release $module ($release_name_metacpan)" );

    # if just the one and only POD from the modules name and not the entire
    # release is wanted, we just fetch ist and return
    if ($dont_merge_release) {

        my $result = $mcpan->pod(  module        => $release_name_metacpan,
                                  'content-type' => 'text/x-pod',
                                );
        my @pod = ();
        my $info = { pod => $result, filename => '', title => $module };
        push (@pod, $info);

        # EXIT!
        return @pod;
    }
    # ELSE we go on and build the entire release...

    my $module_result = $mcpan->fetch( 'release/' . $release_name_metacpan );
    $self->publisher->debug( "103: fetch result: " . Dumper $module_result );

    # get the manifest with module-author and modulename-moduleversion
    $self->publisher->debug( '103: get MANIFEST' );
    my $manifest = $mcpan->source(
        author  => $module_result->{author},
        release => $module_result->{name},
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
    my @pod_files = grep{
        /^.*\.p(?:od|m)\s?/  # all POD everywhere
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

        my ($path) = split /\s/, $file;
        next if $path !~ m{ \. (?:pod|pm|pl) \z }x;

        $file = $path;

        # the call below ($mcpan->pod()) fails if there is no POD in a
        # module so this is why I filter all the modules. I check if they
        # have any line BEGINNING with '=head1' ore similar
        my $source = $mcpan->source(
            author         => $module_result->{author},
            release        => $module_result->{name},
            path           => $file,
        );

        $self->publisher->debug( "103: source of $file found" );

        # The Moose-Project made me write this filtering Regex, because
        # they have .pm's without POD, and also with nonsense POD which
        # still fails if you call $mcpan->pod
        my $pod_src;
        if ( $source =~ m{ ^=head[1234] }xim ) {

            eval {
                $pod_src = $mcpan->pod(
                    author         => $module_result->{author},
                    release        => $module_result->{name},
                    path           => $file,
                    'content-type' => 'text/x-pod',
                );

                1;
            } or do{ $self->publisher->debug( $@ ); next; };

            if (!$pod_src) {
                $self->publisher->debug( "103: empty pod handle" );
                next;
            }

            if ( $pod_src =~ m/ \A ({.*) /x ) {
                $self->publisher->debug( "103: error message: $1" );
            }
            else {
                $self->publisher->debug( "103: got pod" );
            }

            # metacpan always provides utf-8 encoded data, so we have to decode it
            # otherwise the target plugins may produce garbage
            $pod_src = decode( 'utf-8', $pod_src );

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
 
        my $info = { pod => $pod_src, filename => $filename, title => $title };
        push @pod, $info;
        $self->publisher->debug( "103: passed info " . Dumper $info );
    }

    # voilà
    return @pod;
}

1;

=head1 SYNOPSIS

  my $source_options = { type => 'MetaCPAN', module => 'Moose' };
  my $url_source     = EPublisher::Source->new( $source_options );
  my $pod            = $url_source->load_source;

=head1 METHODS

=head2 load_source

  $url_source->load_source;

reads the URL 

=cut
