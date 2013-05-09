#!/usr/bin/perl

use strict;

use Data::Dumper;
use lib "/httpd/modules"; 
use ZOOVY;
use WEBDOC::PODPLAIN;
use Digest::MD5;
use File::Slurp;
#use XML::Twig;
use HTML::TreeBuilder;
#use HTML::TreeBuilder::Xath;

my ($es) = &ZOOVY::getElasticSearch("",'server'=>"db1");

if ($es->index_exists("index"=>"webdoc")) {
	$es->delete_index("index"=>"webdoc");
	}
$es->create_index(
	'index'=>'webdoc'
	);

#my ($p) = HTML::Parser->new( 
#	api_version=>3,
##	start_h => [\&start, "MODULE"],
##	end_h   => [\&end, "MODULE"]
#	);
#my $xs = XML::Simple->new();



sub parseElement {
	my ($el,$meta) = @_;

	# print Dumper($el);
	# print $el->tag()."\n";

	if ($el->tag() eq 'module') {
		my %attr = $el->all_attr();
		my $LIB = $attr{'lib'};

		if ($attr{'pod'}) {
			## POD route
			use IO::String;
			my $io = IO::String->new;

			my ($POD) = $attr{'pod'};
			$POD =~ s/::/\//g;	# convert JQUERY::PARSE to JQUERY/PARSE
			$POD = "/httpd/modules/$POD.pm";

			my $parser = new WEBDOC::PODPLAIN();
			$parser->parse_from_file($POD,$io);
			# my $buf = ${$io->string_ref()};
			# print Dumper($buf);	
			my $html = ${$io->string_ref()};

			my $tree = HTML::TreeBuilder->new(no_space_compacting=>1,ignore_unknown=>0,store_comments=>1); # empty tree
			$tree->parse($html);
			$el->replace_with($tree->elementify());
			}
		elsif ($attr{'eval'}) {
			my $EVAL = $attr{'eval'};
			if (defined $attr{'lib'}) { $EVAL = "require $attr{'lib'};\n$EVAL"; }

			my $html = eval "$EVAL";
			$html = "\n\n<!-- BEGIN $EVAL -->\n\n$html\n\n<!-- END $EVAL -->\n\n\n";
			$html = "<p>$html</p>";
			# print $html."\n";

			## $el->replace_with($html);
			my $tree = HTML::TreeBuilder->new(no_space_compacting=>1,ignore_unknown=>0,store_comments=>1); # empty tree
			$tree->parse_content($html);
			$el->replace_with($tree->elementify());
			}
		}

	foreach my $elx (@{$el->content_array_ref()}) {
		if (ref($elx) eq '') {
			## just content!
			}
		else {
			## print "-- ".$elx->tag()."\n";
			&parseElement($elx);
			}
		}
	return();
	}



opendir my $D, "/httpd/static/webdoc";

while ( my $file = readdir($D) ) {
	next if (substr($file,0,1) eq '.');
	next if (substr($file,0,1) eq '_');
	next if ($file !~ /\.html$/);
	$file =~ s/$\.html$//gs;	# strip trailing .html

	print "FILE: /httpd/static/webdoc/$file.html\n";
	my (@content) = File::Slurp::slurp("/httpd/static/webdoc/$file.html");
	my $content = join("",@content);
	next if ($content eq '');
	# my $w = WEBDOC2->new($content);
	# print length($content)."\n";
	# print $content."\n";

	my %META = ();

#	$BODY = "<meta type=\"keywords\">".join(@TAGS)."</meta>\n".$BODY;
#	$BODY =~ s/\[\[PROSHOP\](.*?)\].*?\[\[\/PROSHOP\]\]/<div class="proshop">$1<\/div>/gs;
#	$BODY =~ s/\[\[MODULE\](.*?)\]/<MODULE CODE="$1" \/>/gs;
#	$BODY =~ s/\[\[MASON\](.*?)\].*?\[\[\/MASON\]\]/<MODULE>$1<\/MODULE>/gs;
#	$BODY =~ s/\[\[POLICY\](.*?)\].*?\[\[\/POLICY\]\]/<div class="policy">$1<\/div>/gs;
#	$BODY =~ s/\[\[LINK\](.*?)\](.*?)\[\[\/LINK\]\]/<a class="link" href=\"#$1\">Link $2<\/a>/gs;
#	$BODY =~ s/\[\[LINKDOC\](.*?)\]/<a class="linkdoc" href=\"#?doc=$1\">Doc $1<\/a>/gsi;
#	$BODY =~ s/\[\[\/LINKDOC\](.*?)\]//gs;
#	$BODY =~ s/\[\[DOCLINK\](.*?)\]/<a class="linkdoc" href=\"#?doc=$1\">Doc $1<\/a>/gsi;
#	$BODY =~ s/\[\[YOUTUBE\](.*?)\]/<a class="linkyoutube" href=\"#?youtube=$1\">Youtube $1<\/a>/gs;

#	$p->parse_file("/httpd/static/webdoc/$file");
#	my $ref = $xs->XMLin("/httpd/static/webdoc/$file");

#	next if ($content !~ /MODULE/);
#	next if ($content !~ /POD/);

	my $tree = HTML::TreeBuilder->new(no_space_compacting=>1,ignore_unknown=>0,store_comments=>1); # empty tree
	$tree->parse_content("$content");

#	print "Hey, here's a dump of the parse tree:\n";
#   $tree->dump; # a method we inherit from HTML::Element
#   print "And here it is, bizarrely rerendered as HTML:\n",
#   $tree->as_HTML, "\n";

	my $el = $tree->elementify();
	&parseElement($el,\%META);

	my $html = $el->as_HTML();
	## print $html."\n";
	
	my $MODIFIED = 0;
	my $MD5new = Digest::MD5::md5_hex($html);
	my $MD5old = undef;
	if (1) {
		my $buf = 0;
		open F, "</httpd/static/webdoc/$file._html";
		while (<F>) { $buf .= $_; }
		close F;
		$MD5old = Digest::MD5::md5_hex($buf);
		}

	print "$MD5new $MD5old\n";

	if ($MODIFIED) {

		print "WRITING: /httpd/static/webdoc/$file.chtml\n";
		open F, ">/httpd/static/webdoc/$file._html";
		print F $html;
		close F;

		$es->index(
			'index'=>'webdoc',
			'type'=>'doc',
			'id'=>"$file",
			'data'=>{ 'body'=>$html }
			);	
		}

	}
closedir $D;

