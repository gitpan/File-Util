
use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded
BEGIN { plan tests => 20, todo => [] }
BEGIN { $| = 1 }

# load your module...
use lib './';
use File::Util qw( SL );

my($f) = File::Util->new();

my(@fls) = ( qq[t${\SL}txt], qq[t${\SL}bin], 't' );

# types
ok(join('',@{[$f->file_type($fls[0])]}), 'plaintext');
ok(join('',@{[$f->file_type($fls[1])]}), 'plainbinary');
ok(join('',@{[$f->file_type($fls[2])]}), 'directory');

# file is/isn't binary
ok($f->isbin($fls[1], 1));
ok(!$f->isbin(__FILE__));

foreach (@fls) {

   my($file) = $_;

   # get file size
   ok($f->size($file), -s $file);

   # get file creation time
   ok($f->created($file),$^T - ((-M $file) * 60 * 60 * 24));

   # get file last access time
   ok($f->last_access($file),$^T - ((-A $file) * 60 * 60 * 24));

   # get file last modified time
   ok($f->last_mod($file),$^T - ((-C $file) * 60 * 60 * 24));

   # get file's bitmask
   ok($f->bitmask($file),sprintf('%04o',(stat($file))[2] & 0777));
}

exit;