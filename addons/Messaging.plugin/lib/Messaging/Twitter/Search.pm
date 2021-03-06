package Messaging::Twitter::Search;

use base qw( Messaging::Twitter );
use Messaging::Twitter::Util
  qw( serialize_author twitter_date truncate_tweet serialize_entries is_number 
      load_friends load_followers latest_status mark_favorites );

use MT::Util qw( decode_url encode_url );

=head2 search

URL:
http://search.twitter.com/search.format
 
Formats: 
json, atom 
 
HTTP Method:
GET
 
Requires Authentication (about authentication):
false
 
API rate limited (about rate limiting):
1 call per request
 
Parameters:

q: Required. Should be URL encoded. Queries will be limited by complexity.
    http://search.twitter.com/search.json?q=@noradio

callback: Optional. Only available for JSON format. If supplied, the response
will use the JSONP format with a callback of the given name.

lang: Optional: Restricts tweets to the given language, given by an ISO 639-1
code.

locale: Optional. Specify the language of the query you are sending (only ja
is currently effective). This is intended for language-specific clients and
the default should work in the majority of cases.

rpp: Optional. The number of tweets to return per page, up to a max of 100.

page: Optional. The page number (starting at 1) to return, up to a max of
roughly 1500 results (based on rpp * page. Note: there are pagination limits.

since_id: Optional. Returns tweets with status ids greater than the given id.

geocode: Optional. Returns tweets by users located within a given radius of
the given latitude/longitude. The location is preferentially taking from the
Geotagging API, but will fall back to their Twitter profile. The parameter
value is specified by "latitide,longitude,radius", where radius units must be
specified as either "mi" (miles) or "km" (kilometers). Note that you cannot
use the near operator via the API to geocode arbitrary locations; however you
can use this geocode parameter to search near geocodes directly.

show_user: Optional. When true, prepends "<user>:" to the beginning of the
tweet. This is useful for readers that do not display Atom's author field. The
default is false.

JSON example (truncated):
  {"results":[
     {"text":"@twitterapi  http:\/\/tinyurl.com\/ctrefg",
     "to_user_id":396524,
     "to_user":"TwitterAPI",
     "from_user":"jkoum",
     "id":1478555574,   
     "from_user_id":1833773,
     "iso_language_code":"nl",
     "source":"<a href="http:\/\/twitter.com\/">twitter<\/a>",
     "profile_image_url":"http:\/\/s3.amazonaws.com\/twitter_production\/profile_images\/118412707\/2522215727_a5f07da155_b_normal.jpg",
      "created_at":"Wed, 08 Apr 2009 19:22:10 +0000"},
     ... truncated ...],
     "since_id":0,
     "max_id":1480307926,
     "refresh_url":"?since_id=1480307926&q=%40twitterapi",
     "results_per_page":15,
     "next_page":"?page=2&max_id=1480307926&q=%40twitterapi",
     "completed_in":0.031704,
     "page":1,
     "query":"%40twitterapi"}
  }

=cut

sub search {
    my $app      = shift;
    my ($params) = @_;

    # The word to search on
    my $q = decode_url( $params->{q} );

    # Give up if there is no search keyword.
    return { results => '' } if !$q;

    # Search terms to set limit and offset
    my $terms = {};
    $terms->{limit}     = $params->{rpp}  ? $params->{rpp}  : 15;
    $terms->{offset}    = $params->{page} ? ($params->{page} - 1) * $terms->{limit} : 0;
    $terms->{sort_by}      = 'created_on';
    $terms->{direction} = 'descend';
    $terms->{range} = { object_id => 1 };
    my $since_id = $params->{since_id} ? $params->{since_id} : 0;
    my $max_id = $params->{max_id} ? $params->{max_id} : '99999999999999';
    my $page = $params->{page} ? $params->{page} : 1;
    my $rpp = $params->{rpp} ? $params->{rpp} : 15;
    # Hold the selected messages in @messages.
    my @messages;

    # If the search term starts with a hash, it must be a tag search. This 
    # works for both normal and private hashtags.
    if ( $q =~ /^\#/ ) {
        # Load the specified tag
        my $tag = MT->model('tag')->load({ name => $q })
            or return { results => '' }; # Give up if no tag found

        # Now use that tag to find the tag-message intersections
        my $iter = MT->model('objecttag')->load_iter(
            {
                object_datasource => 'tw_message',
                tag_id     => $tag->id,
                object_id => [ $since_id, $max_id ],
            },
           $terms
        );

        # Now we know which messages use this tag, so we can grab them to 
        # return the search results.
        while ( my $objecttag = $iter->() ) {
            my $message = MT->model('tw_message')->load({ id => $objecttag->object_id })
                or next;
            push @messages, $message;
        }
    }

    # This is a straight keyword search.
    else {
        # Use "like" to do the search along with anything ("%") before and
        # after the keyword to find all matches.
        @messages = MT->model('tw_message')->load(
            {
                text => { like => "%$q%" },
                id => [ $since_id, $max_id ],
            },
            $terms,
        );
    }

    my $statuses = serialize_entries( \@messages );

    # If max_id was not set as a parameter, show the highest id in the current page of results
    # If it has been set, show its value (the current results page will be paginated started from this
    # ID in this case.)
    
    if ($max_id eq '99999999999999'){$max_id = $messages[0]->id}
    
    my $nextpageparameters = "?q=".encode_url($q)."&page=".($page+1);
    if ($rpp and ($rpp != 15)) {$nextpageparameters .= "&rpp=".$rpp;}
    $nextpageparameters .= "&max_id=".$max_id;
    
    my $refreshpageparameters = "since_id=$max_id&q=".encode_url($q);
    
    return { results => $statuses, 
    	    page => $page, 
    	    max_id => $max_id, 
    	    next_page => $nextpageparameters ,
    	    query => "$q",
    	    refresh_url => $refreshpageparameters,
    	    since_id => $since_id, 
    	    results_per_page => $rpp? $rpp : 15,
    };
}

=head2 trends

Variants: trends/(current|daily|weekly)

=cut

sub trends {

}

1;
__END__
