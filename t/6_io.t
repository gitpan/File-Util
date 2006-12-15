
use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded
BEGIN { plan tests => 41, todo => [] }
BEGIN { $| = 1 }

# load your module...
use lib './';
use File::Util qw( SL NL existent );

my($f)   = File::Util->new();
my($fh)  = undef;
my($testbed) = 't/' . $$;

# make a temporary testbed directory
ok($f->make_dir($testbed), $testbed);

# see if it's there
ok(-e $testbed, 1);

# ...again
ok($f->existent($testbed), 1);

# directory listing
{
   my(@opts) = qw/--files-only --with-paths/;
   my(@lines) = $f->load_file('MANIFEST','--as-list');

   map { ok($f->existent($_) and -e $_) } $f->list_dir('.', @opts);
   map {
      next if !length($_);
      next if $_ =~ /^META\.yml/o;
      ok(existent($_) and -e $_)
   } @lines;
}

# make a temporary file
my($tmpf) = $testbed . SL . 'tmptst';
ok($f->write_file('file' => $tmpf, 'content' => $$ . NL),$$ . NL);

# get an open file handle
ok
   (
      sub { $fh = $f->open_handle( 'file' => $tmpf, 'mode' => 'append' ); $fh },
      '/\*File\:\:Util\:\:OPEN\_TO\_FH/'
   );

# make sure it's still open
ok(fileno($fh), '/^\d/');

# write to it, close it, write to it in append mode
print( $fh 'Hello world!' . NL ); close($fh);

# load file
ok($f->load_file($tmpf),$f->load_file($tmpf));

# write to it with method File::Util::write_file(), compare file contents
# with the returned value
ok
   (
      $f->write_file
         (
            'filename' => $tmpf,
            'content'  => ( $^O || 'foo' ) . NL,
            'mode'     => 'append',
         ),
   );

# get line count of file
ok($f->line_count($tmpf),3);

# truncate file
ok(sub { $f->trunc($tmpf); -s $tmpf }, 0);

# get line count of file
ok($f->line_count($tmpf),0);

# big directory creation / removal sequence
my($newdir) =
  $testbed
  . SL . int(rand(time))
  . SL . int(rand(time))
  . SL . int(rand(time))
  . SL . int(rand(time));

# make directories
ok($f->make_dir($newdir, '--if-not-exists'), $newdir);

# read directories
my(@items) = $f->list_dir($testbed, '--follow');

# remove directories, temp file, testbed.
foreach (reverse(sort({ length($a) <=> length($b) } @items)), $testbed) {

   -d $_ ? rmdir($_) || &_rmdie($!) : unlink($_) || &_uldie($!);
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
