
use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded
BEGIN { plan tests => 12, todo => [] }
BEGIN { $| = 1 }

# load your module...
use lib './';
use File::Util qw( SL NL existent );

my($f)    = File::Util->new('--fatals-as-status');
my($fh)   = undef;
my($testbed) = 't' . SL . $$;
my($skip) = !$f->can_write('.') ||
            !$f->can_write('t');

$skip = $skip ? <<'__WHYSKIP__' : $skip;
Insufficient permissions to perform IO in this directory.  Can't perform tests!
__WHYSKIP__

# make a temporary testbed directory
skip($skip, sub { $f->make_dir($testbed, '--if-not-exists') }, $testbed);

# see if it's there
skip($skip, -e $testbed, 1, $skip);

# ...again
skip($skip, sub { $f->existent($testbed) }, 1, $skip);

# make a temporary file
my($tmpf) = $testbed . SL . 'tmptst';
skip(
	$skip,
	sub {
		$f->write_file('file' => $tmpf, 'content' => $$ . NL),
	}, 1, $skip
);

# get an open file handle
$fh = 'Unable to open file handle for unknown reason';
skip(
	$skip,
	sub {
      $fh = $f->open_handle(
         'file' => $tmpf,
         'mode' => 'append',
         '--fatals-as-errmsg'
      );
      return $fh;
   },
	'/\*File\:\:Util\:\:OPEN\_TO\_FH/',
   $fh,
);

# make sure it's still open
skip($skip, eval(q{fileno($fh)}), '/^\d/', $skip);

# write to it, close it, write to it in append mode
unless ($skip) { print( $fh 'Hello world!' . NL ); close($fh); }

# load file
skip($skip, sub { $f->load_file($tmpf),$f->load_file($tmpf) });

# write to it with method File::Util::write_file(), compare file contents
# with the returned value
skip (
	$skip,
	sub {
		$f->write_file(
			'filename' => $tmpf,
			'content'  => ( $^O || 'foo' ) . NL,
			'mode'     => 'append',
		)
	}, 1, $skip
);

# get line count of file
skip($skip, sub { $f->line_count($tmpf) }, 3, $skip);

# truncate file
skip($skip, sub { $f->trunc($tmpf); -s $tmpf }, 0, $skip);

# get line count of file
skip($skip, sub { $f->line_count($tmpf)}, 0, $skip);

# big directory creation / removal sequence
my($newdir) =
  $testbed
  . SL . int(rand(time))
  . SL . int(rand(time))
  . SL . int(rand(time))
  . SL . int(rand(time));

# make directories
skip($skip, sub { $f->make_dir($newdir, '--if-not-exists') }, $newdir, $skip);

# read directories
unless ($skip) {
	my(@items) = $f->list_dir($testbed, '--follow');

	# remove directories, temp file, testbed.
	foreach (reverse(sort({ length($a) <=> length($b) } @items)), $testbed) {

		-d $_ ? rmdir($_) || &_rmdie($!) : unlink($_) || &_uldie($!);
	}
}

exit;

# ---- SUBS -----------------------------------------------

sub _uldie { die(<<__BADUNLINK__) }
Can't unlink recently created temp file used in testing process.
$!
__BADUNLINK__

sub _rmdie { die(<<__BADRMDIR__) }
Can't remove recently created temporary directory used in testing process.
$!
__BADRMDIR__
