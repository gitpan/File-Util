package File::Util;
use 5.006;
use strict;
use warnings;
use vars qw
   (
      $VERSION   @ISA   @EXPORT_OK   %EXPORT_TAGS
      $OS   $MODES   $READLIMIT   $MAXDIVES   $EMPTY_WRITES_OK
      $USE_FLOCK   @ONLOCKFAIL   $ILLEGAL_CHR   $CAN_FLOCK
      $NEEDS_BINMODE   $EBCDIC   $DIRSPLIT   $SL   $NL
   );
use Exporter;
use AutoLoader qw( AUTOLOAD );
use Class::OOorNO qw( :all );
$VERSION    = 3.14_0; # 12/28/02, 12:43 pm
@ISA        = qw( Exporter   Class::OOorNO );
@EXPORT_OK  =
   (
      @Class::OOorNO::EXPORT_OK, qw
         (
            can_flock   ebcdic   existent   isbin   bitmask   NL   SL
            strip_path   can_read   can_write   file_type   needs_binmode
            valid_filename   size   escape_filename   os
         )
   );
%EXPORT_TAGS = ( 'all'  => [ @EXPORT_OK ] );

BEGIN {

   # Some OS logic.
   unless ($OS = $^O) { require Config; eval(q[$OS=$Config::Config{osname}]) }

      if ($OS =~ /^darwin/i) { $OS = 'UNIX'      }
   elsif ($OS =~ /^cygwin/i) { $OS = 'CYGWIN'    }
   elsif ($OS =~ /^MSWin/i)  { $OS = 'WINDOWS'   }
   elsif ($OS =~ /^vms/i)    { $OS = 'VMS'       }
   elsif ($OS =~ /^bsdos/i)  { $OS = 'UNIX'      }
   elsif ($OS =~ /^dos/i)    { $OS = 'DOS'       }
   elsif ($OS =~ /^MacOS/i)  { $OS = 'MACINTOSH' }
   elsif ($OS =~ /^epoc/)    { $OS = 'EPOC'      }
   elsif ($OS =~ /^os2/i)    { $OS = 'OS2'       }
                        else { $OS = 'UNIX'      }

$EBCDIC = qq[\t] ne qq[\011];
$NEEDS_BINMODE = $OS =~ /WINDOWS|DOS|OS2|MSWin/;
$NL =
   $NEEDS_BINMODE ? qq[\015\012]
      : $EBCDIC || $OS eq 'VMS' ? qq[\n]
         : $OS eq 'MACINTOSH' ? qq[\015]
            : qq[\012];
$SL =
   { 'DOS' => '\\', 'EPOC'   => '/', 'MACINTOSH' => ':',
     'OS2' => '\\', 'UNIX'   => '/', 'WINDOWS'   => '\\',
     'VMS' => '/',  'CYGWIN' => '/', }->{ $OS }||'/';

} BEGIN { use constant NL => $NL; use constant SL => $SL; }

$DIRSPLIT = qr/${\quotemeta($SL)}/;
$ILLEGAL_CHR = qr/[\/\|$NL\r\n\t\013\*\"\?\<\:\>\\]/;

$READLIMIT  = 10000000; # set readlimit to a default of 10 megabytes
$MAXDIVES   = 500;      # maximum depth for recursive list_dir calls

use Fcntl qw( );

{ local($@); eval <<'__canflock__'; $CAN_FLOCK = $@ ? 0 : 1; }
flock(STDOUT, &Fcntl::LOCK_SH);
flock(STDOUT, &Fcntl::LOCK_UN);
__canflock__

# try to use file locking, define flock race conditions policy
$USE_FLOCK = 1; @ONLOCKFAIL = qw( BLOCK FAIL );

$MODES->{'popen'} =
{
   'write'  => '>',  'trunc'  => '>',
   'append' => '>>', 'read'   => '<',
};

$MODES->{'sysopen'} =
{
   'read'    => '&Fcntl::O_RDONLY',
   'write'   => '&Fcntl::O_WRONLY | &Fcntl::O_CREAT',
   'append'  => '&Fcntl::O_WRONLY | &Fcntl::O_APPEND | &Fcntl::O_CREAT',
   'trunc'   => '&Fcntl::O_WRONLY | &Fcntl::O_CREAT  | &Fcntl::O_TRUNC',
};

# --------------------------------------------------------
# Constructor
# --------------------------------------------------------
sub new {

   my($this) = {}; bless($this, shift(@_));
   my($in)   = $this->coerce_array(@_);

   my($opts) = $this->shave_opts(\@_);
   $this->{'opts'} = $opts || {};

   $USE_FLOCK  = $$in{'use_flock'} if defined($$in{'use_flock'});
   $READLIMIT  = $$in{'readlimit'} if defined($$in{'readlimit'});
   $MAXDIVES   = $$in{'max_dives'} if defined($$in{'max_dives'});
   @ONLOCKFAIL = split(/ /,$$in{'flock_rules'}) if defined($$in{'flock_rules'});

   $this;
}


# File::Util::--------------------------------------------
#   can_read()   can_write()
# --------------------------------------------------------
sub can_read  { my($f) = myargs(@_); $f ? -r $f : undef }
sub can_write { my($f) = myargs(@_); $f ? -w $f : undef }


# --------------------------------------------------------
# File::Util::list_dir()
# --------------------------------------------------------
sub list_dir {

   my($this) = shift(@_);
   my($opts) = $this->shave_opts(\@_);
   my($dir)  = shift(@_)||'.';
   my($path) = $dir;
   my($r)    = 0;
   my(@dirs) = (); my(@files) = (); my(@items) = ();

   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'list_dir',
                  'missing'   => 'a directory name',
                  'opts'      => $opts,
               }
            )
      )
         unless length($dir);

   return($this->_throw('no such file', { 'filename' => $dir })) unless -e $dir;

   if ($opts->{'--recursing'}) { ++$this->{'recursed'} }
   else { $this->{'recursed'} = 0 }

   if ($this->{'recursed'} >= $MAXDIVES) {

      return($this->_throw(<<__rbail__))

Recursion limit reached at $MAXDIVES dives.  Maximum number of subdirectory
dives is set to the value returned by File::Util::max_dives().  Try manually
setting the value to a higher number before calling list_dir() with option
--follow or --recurse (synonymous).  Do so by calling File::Util::max_dives()
with the numeric argument corresponding to the maximum number of subdirectory
dives you want to allow when traversing directories recursively.

This operation aborted.

__rbail__
   }

   $r = 1 if ($opts->{'--follow'} || $opts->{'--recurse'});

   # whack off any trailing directory separator
   unless (length($dir) == 1)
   { $dir =~ s/$DIRSPLIT$//o; $path =~ s/$DIRSPLIT$//o; }

   return
      (
         $this->_throw
            (
               'called opendir on a file',
               {
                  'filename'  => $dir,
                  'opts'      => $opts,
               }
            )
      )
         unless (-d $dir);

   local(*DIR);

   opendir(DIR, $dir) or
      return
         (
            $this->_throw
               (
                  'bad opendir',
                  {
                     'dir'       => $dir,
                     'exception' => $!,
                     'opts'      => $opts,
                  }
               )
         );

   # read from beginning of the directory (doesn't seem necessary on any
   # platforms I've run code on, but just in case...)
   rewinddir(DIR);

   if ($opts->{'--count-only'}) {

      my($i) = 0; my($o) = '';

      while ($o = readdir(DIR)) { ++$i unless (($o eq '.')||($o eq '..')) }

      return($i);
   }

   @files =
      exists($opts->{'--pattern'})
      ? grep(/$opts->{'--pattern'}/, readdir(DIR))
      : readdir(DIR);

   closedir(DIR) or
      return
         (
            $this->_throw
               (
                  'close dir',
                  {
                     'dir'       => $dir,
                     'exception' => $!,
                     'opts'      => $opts,
                  }
               )
         );

   if ($opts->{'--no-fsdots'}) {

      my(@shadow) = @files; @files = ();

      while (@shadow) {

         my($f) = shift(@shadow);

         push(@files,$f)
            unless
               (
                  $this->strip_path($f) eq '.'
                     or
                  $this->strip_path($f) eq '..'
               );
      }
   }

   for (my($i) = 0; $i < @files; ++$i) {

      my($listing) =
         ($opts->{'--with-paths'} or ($r==1))
            ? $path . $SL . $files[$i]
            : $files[$i];

      if (-d $path . $SL . $files[$i]) { push(@dirs, $listing) }
      else { push(@items, $listing) }
   }

   if  (($r) and (not $opts->{'--override-follow'})) {

      my(@shadow) = @dirs; @dirs = ();

      while (@shadow) {

         my($f) = shift(@shadow);

         push(@dirs,$f)
            unless
               (
                  $this->strip_path($f) eq '.'
                     or
                  $this->strip_path($f) eq '..'
               );
      }

      for (my($i) = 0; $i < @dirs; ++$i) {

         my(@lsts) = $this->list_dir
            (
               $dirs[$i],
               '--with-paths',   '--dirs-as-ref',
               '--files-as-ref', '--recursing',
               '--no-fsdots',
            );

         push(@dirs,@{$lsts[0]}); push(@items,@{$lsts[1]});
      }
   }

   if ($opts->{'--sl-after-dirs'}) {

      @dirs       = $this->_dropdots(@dirs,'--save-dots');
      my($dots)   = shift(@dirs);
      @dirs       = map ( ($_ .= $SL), @dirs );
      @dirs       = (@{$dots},@dirs);
   }

   my($reta) = []; my($retb) = [];

   if ($opts->{'--ignore-case'}) {

      $reta = [ sort {uc $a cmp uc $b} @dirs  ];
      $retb = [ sort {uc $a cmp uc $b} @items ];
   }
   else {

      $reta = [ sort {$a cmp $b} @dirs  ];
      $retb = [ sort {$a cmp $b} @items ];
   }

   $reta=[$reta]  if ($opts->{'--dirs-as-ref'}  || $opts->{'--as-ref'});
   $retb=[$retb]  if ($opts->{'--files-as-ref'} || $opts->{'--as-ref'});
   return(@$reta) if ($opts->{'--dirs-only'});
   return(@$retb) if ($opts->{'--files-only'});

   return(@$reta,@$retb);
}


# --------------------------------------------------------
# File::Util::_dropdots()
# --------------------------------------------------------
sub _dropdots {

   my($this) = shift(@_); my(@out) = (); my($opts) = $this->shave_opts(\@_);
   my(@shadow) = @_; my(@dots) = (); my($gottadot) = 0;

   while (@shadow) {

      if ($gottadot == 2){ push(@out,@shadow) and last }

      my($thing) = shift(@shadow);

      if ($thing eq '.')  {++$gottadot;push(@dots,$thing);next}
      if ($thing eq '..') {++$gottadot;push(@dots,$thing);next}

      push(@out,$thing);
   }

   return([@dots],@out) if ($opts->{'--save-dots'}); @out;
}


# --------------------------------------------------------
# File::Util::load_file()
# --------------------------------------------------------
sub load_file {

   my($this) = shift(@_); my($opts) = $this->shave_opts(\@_);
   my($in) = $this->coerce_array(@_); my(@dirs) = ();
   my($blocksize) = 1024; # 1.24 kb
   my($FH_passed) = 0; my($fh) = undef; my($file) = ''; my($path) = '';
   my($content)   = ''; my($FHstatus) = ''; my($mode) = 'read';

   if (scalar(@_) == 1) {

      $file = shift(@_)||'';

      @dirs = split(/$DIRSPLIT/, $file);

      if (scalar(@dirs) > 0) {

         $file = pop(@dirs); $path = join($SL, @dirs);
      }

      if (length($path) > 0) {

         $path = '.' . $SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
      }
      else { $path = '.'; }

      return
         (
            $this->_throw
               (
                  'no input',
                  {
                     'meth'      => 'load_file',
                     'missing'   => 'a file name or file handle reference',
                     'opts'      => $opts,
                  }
               )
         )
            if (length($path . $SL . $file) == 0);
   }
   else {

      $fh = $in->{'FH'}||''; $FHstatus = $in->{'FH_status'}||'';

      # did we get a filehandle?
      if (length($fh) > 0) { $FH_passed = 1; } else {

         return
            (
               $this->_throw
                  (
                     'no input',
                     {
                        'meth'      => 'load_file',
                        'missing'   => 'a file name or file handle reference',
                        'opts'      => $opts,
                     }
                  )
            );
      }
   }

   if ($FH_passed) {

      my($buff) = 0; my($bytes_read) = 0;

      while (<$fh>) {

         if ($buff < $READLIMIT) {

            $bytes_read = read($fh, $content, $blocksize); $buff += $bytes_read;
         }
         else {

            return
               (
                  $this->_throw
                     (
                        'readlimit exceeded',
                        {
                           'filename'  => '<FH>',
                           'size'      => qq[[truncated at $bytes_read]],
                           'opts'      => $opts,
                        }
                     )
               );
         }
      }

      # return an array of all lines in the file if the call to this method/
      # subroutine asked for an array eg- my(@file) = load_file('file');
      # otherwise, return a scalar value containing all of the file's content
      return(split(/$NL|\r|\n/o,$content)) if $opts->{'--as-list'};

      return($content);
   }

   # if the file doesn't exist, send back an error
   return
      (
         $this->_throw
            (
               'no such file',
               {
                  'filename'  => $path . $SL . $file,
                  'opts'      => $opts,
               }
            )
      )
         unless -e $path . $SL . $file;

   # it's good to know beforehand whether or not we have permission to open
   # and read from this file allowing us to handle such an exception before
   # it handles us.

   # first check the readability of the file's housing dir
   return
      (
         $this->_throw
            (
               'cant dread',
               {
                  'filename'  => $path . $SL . $file,
                  'dirname'   => $path . $SL,
                  'opts'      => $opts,
               }
            )
      )
         unless ($this->can_read($path . $SL));

   # now check the readability of the file itself
   return
      (
         $this->_throw
            (
               'cant fread',
               {
                  'filename'  => $path . $SL . $file,
                  'dirname'   => $path . $SL,
                  'opts'      => $opts,
               }
            )
      )
         unless ($this->can_read($path . $SL . $file));

   # if the file is a directory it will not be opened
   return
      (
         $this->_throw
            (
               'called open on a dir',
               {
                  'filename'  => $path . $SL . $file,
                  'opts'      => $opts,
               }
            )
      )
         if -d $path . $SL . $file;

   return($this->_throw( qq[
      $this->{'name'} can't open " $file " for reading because
      it is a a block special file.] ))
         if (-b $path . $SL . $file);

   my($fsize) = -s $path . $SL . $file;

   return
      (
         $this->_throw
            (
               'readlimit exceeded',
               {
                  'filename'  => $path . $SL . $file,
                  'size'      => $fsize,
                  'opts'      => $opts,
               }
            )
      )
         if ($fsize > $READLIMIT);

   # we need a unique filehandle
   do { $fh = int(rand(time)) . $$; $fh = eval('*' . 'LOAD_FILE' . $fh) }
   while fileno($fh);

   # localize the global output record separator so we can slurp it all
   # in one quick read.  We fail if the filesize exceeds our limit.
   local($/);

   # open the file for reading (note the '<' syntax there) or fail with a
   # error message if our attempt to open the file was unsuccessful
   my($cmd) = '<' . $path . $SL . $file;

   # lock file before I/O on platforms that support it
   if ($$opts{'--no-lock'} || $$this{'opts'}{'--no-lock'}) {

      # if you use the '--no-lock' option you are probably stupid
      open($fh, $cmd) or
         return
            (
               $this->_throw
                  (
                     'bad open',
                     {
                        'filename'  => $path . $SL . $file,
                        'mode'      => $mode,
                        'exception' => $!,
                        'cmd'       => $cmd,
                        'opts'      => $opts,
                     }
                  )
            );
   }
   else {

      open($fh, $cmd) or
         return
            (
               $this->_throw
                  (
                     'bad open',
                     {
                        'filename'  => $path . $SL . $file,
                        'mode'      => $mode,
                        'exception' => $!,
                        'cmd'       => $cmd,
                        'opts'      => $opts,
                     }
                  )
            );

      $this->_seize($path . $SL . $file, $fh);
   }

   # call binmode on binary files for portability accross platforms such
   # as MS flavor OS family
   CORE::binmode($fh) if (-B $path . $SL . $file);

   # assign the content of the file to this lexically scoped scalar variable
   # (memory for *that* variable will be freed when execution leaves this
   # method / sub
   $content = <$fh>;

   if ($$opts{'--no-lock'} || $$this{'opts'}{'--no-lock'}) {

      # if execution gets here, you used the '--no-lock' option, and you
      # are probably stupid
      close($fh) or
         return
            (
               $this->_throw
                  (
                     'bad close',
                     {
                        'filename'  => $path . $SL . $file,
                        'mode'      => $mode,
                        'exception' => $!,
                        'opts'      => $opts,
                     }
                  )
            );
   }
   else {

      # release shadow-ed locks on the file
      $this->_release($fh);

      close($fh) or
         return
            (
               $this->_throw
                  (
                     'bad close',
                     {
                        'filename'  => $path . $SL . $file,
                        'mode'      => $mode,
                        'exception' => $!,
                        'opts'      => $opts,
                     }
                  )
            );
   }

   # return an array of all lines in the file if the call to this method/
   # subroutine asked for an array eg- my(@file) = load_file('file');
   # otherwise, return a scalar value containing all of the file's content
   return(split(/$NL|\r|\n/o,$content))
      if $opts->{'--as-lines'}
      || $opts->{'--as-list'};

   $content;
}


# --------------------------------------------------------
# File::Util::write_file()
# --------------------------------------------------------
sub write_file {

   my($this)      = shift(@_);
   my($opts)      = $this->shave_opts(\@_);
   my($in)        = $this->coerce_array(@_);
   my($filename)  = $in->{'file'}      || '';
   my($content)   = $in->{'content'}   || '';
   my($mode)      = $in->{'mode'}      || 'write';
   my($bitmask)   = $in->{'bitmask'}   || 0777;
   my($path)      = '';
   my(@dirs)      = ();

   $filename ||= $$in{'filename'}; $filename ||= ''; $path = $filename;

   local(*WRITE_FILE); $mode = 'trunc' if ($mode eq 'truncate');

   # if the call to this method didn't include a filename to which the caller
   # wants us to write, then complain about it
   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'write_file',
                  'missing'   => 'a file name to create, write, or append',
                  'opts'      => $opts,
               }
            )
      )
         unless length($filename);

   # if prospective filename contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return
      (
         $this->_throw
            (
               'bad chars',
               {
                  'string'    => $filename,
                  'purpose'   => 'the name of a file or directory',
                  'opts'      => $opts,
               }
            )
      )
         if ($filename =~ /(?:$DIRSPLIT){2,}/);

   # if the call to this method didn't include any data which the caller
   # wants us to write or append to the file, then complain about it
   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'write_file',
                  'missing'   => 'the content you want to write or append',
                  'opts'      => $opts,
               }
            )
      )
         if
            (
               (length($content) == 0)
                  and
               ($mode ne 'trunc')
                  and
               (!$EMPTY_WRITES_OK)
                  and
               (!$opts->{'--empty-writes-OK'})
            );

   # take care of idiots.  HEY!  I resent that!
   $filename =~ s/$DIRSPLIT$//;

   # determine existance of the file path, make directory(ies) for the
   # path if the full directory path doesn't exist
   @dirs = split(/$DIRSPLIT/, $filename);

   # if prospective file name has illegal chars then complain
   foreach (@dirs) {

      return
         (
            $this->_throw
               (
                  'bad chars',
                  {
                     'string'    => $_,
                     'purpose'   => 'the name of a file or directory',
                     'opts'      => $opts,
                  }
               )
         )
            if (!$this->valid_filename($_));
   }

   if (scalar(@dirs) > 0) {

      $filename = pop(@dirs); $path = join($SL, @dirs);
   }

   if (length($path) > 0) {

      $path = '.' . $SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
   }
   else { $path = '.'; }

   if (!(-e $path)) { $this->make_dir($path, $bitmask); }

   my($openarg) = qq[$path$SL$filename];

   if (-e $openarg) {

      return
         (
            $this->_throw
               (
                  'cant fwrite',
                  {
                     'filename'  => $openarg,
                     'dirname'   => $path . $SL,
                     'opts'      => $opts,
                  }
               )
         )
            unless ($this->can_write($openarg));
   }
   else {

      # if file doesn't exist, the error is one of creation
      return
         (
            $this->_throw
               (
                  'cant fcreate',
                  {
                     'filename'  => $openarg,
                     'dirname'   => $path . $SL,
                     'opts'      => $opts,
                  }
               )
         )
            unless ($this->can_write($path . $SL));
   }

   if ($$opts{'--no-lock'} || !$USE_FLOCK) {

      # get open mode
      $mode = $$MODES{'popen'}{ $mode };

      # if you use the '--no-lock' option you are probably stupid
      open(WRITE_FILE, $mode . $openarg) or
         return
            (
               $this->_throw
                  (
                     'bad open',
                     {
                        'filename'  => $openarg,
                        'mode'      => $mode,
                        'exception' => $!,
                        'cmd'       => $mode . $openarg,
                        'opts'      => $opts,
                     }
                  )
            );
   }
   else {

      # open read-only first to safely check if we can get a lock.
      if (-e $openarg) {

         open(WRITE_FILE, '<' . $openarg) or
            return
               (
                  $this->_throw
                     (
                        'bad open',
                        {
                           'filename'  => $openarg,
                           'mode'      => 'read',
                           'exception' => $!,
                           'cmd'       => $mode . $openarg,
                           'opts'      => $opts,
                        }
                     )
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, *WRITE_FILE);

         return($lockstat) unless $lockstat;

         sysopen(WRITE_FILE, $openarg, eval($$MODES{'sysopen'}{ $mode }))
            or return
               (
                  $this->_throw
                     (
                        'bad open',
                        {
                           'filename'  => $openarg,
                           'mode'      => $mode,
                           'opts'      => $opts,
                           'exception' => $!,
                           'cmd'       => qq[$openarg, ]
                                       . eval($$MODES{'sysopen'}{ $mode }),
                        }
                     )
               );
      }
      else {

         sysopen(WRITE_FILE, $openarg, eval($$MODES{'sysopen'}{ $mode }))
            or return
               (
                  $this->_throw
                     (
                        'bad open',
                        {
                           'filename'  => $openarg,
                           'mode'      => $mode,
                           'opts'      => $opts,
                           'exception' => $!,
                           'cmd'       => qq[$openarg, ]
                                       . eval($$MODES{'sysopen'}{ $mode }),
                        }
                     )
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, *WRITE_FILE);

         return($lockstat) unless $lockstat;
      }

      # now truncate
      if ($mode ne 'append') {

         truncate(WRITE_FILE,0) or
            return
               (
                  $this->_throw
                     (
                        'bad systrunc',
                        {
                           'filename'  => $openarg,
                           'exception' => $!,
                           'opts'      => $opts,
                        }
                     )
               );
      }
   }

   $in->{'content'}||=''; syswrite(WRITE_FILE, $in->{'content'});

   # release lock on the file
   unless ($$opts{'--no-lock'} || !$USE_FLOCK) { $this->_release(*WRITE_FILE) }

   close(WRITE_FILE) or
      return
         (
            $this->_throw
               (
                  'bad close',
                  {
                     'filename'  => $openarg,
                     'mode'      => $mode,
                     'exception' => $!,
                     'opts'      => $opts,
                  }
               )
         );

   return($in->{'content'});
}


# --------------------------------------------------------
# File::Util::_seize()
# --------------------------------------------------------
sub _seize {

   my($this)   = shift(@_); my($file) = shift(@_)||''; my($fh) = shift(@_)||'';
   my(@policy) = @ONLOCKFAIL;
   my($policy) = {}; map { $policy->{$_} = $_ } @policy;

   return($fh) if !$CAN_FLOCK;

# =for nobody

   # OPTIONS ON I/O RACE CONDITION POLICY

      # Set internal file locking rules by calling File::Util::flock_rules()
      # with a list or array containing your chosen directive keywords by order
      # of precedence.

         # ex- flock_rules( qw/ BLOCK FAIL / );  # this is the default rule

   # KEYWORDS

      # BLOCK         waits to try getting an exclusive lock
      # FAIL          fails with stack trace
      # WARN          CORE::warn() about the error with a stack trace
      # IGNORE        ignores the failure to get an exclusive lock
      # UNDEF         returns undef
      # ZERO          returns 0

# =cut

   return($this->_throw(q[no file name passed to _seize.])) unless $file;
   return($this->_throw(q[no handle passed to _seize.]))    unless $fh;

   # seize filehandle, return it if lock is successful
   if (flock($fh, &Fcntl::LOCK_EX | &Fcntl::LOCK_NB)) { return($fh); }
   # process flock failure ruleset if the above attempt failed.
   else {

      # IGNORE directive processed here
      return($fh) if $policy->{'IGNORE'};

      # BLOCK directive processed here
      if ($policy->{'BLOCK'}) {

         if (flock($fh, &Fcntl::LOCK_EX)) { return($fh) } else {

            # ZERO directive processed here if BLOCK directive fails
            if ($policy->{'ZERO'}) { return 0 }

            # UNDEF directive processed here if BLOCK directive fails
            elsif ($policy->{'UNDEF'}) { return undef }

            # WARN directive processed here if BLOCK directive fails
            elsif ($policy->{'WARN'})  {

               $this->_throw
                  (
                     'bad lock',
                     {
                        'filename'  => $file,
                        'exception' => $!,
                     },
                     '--as-warning',
                  );

               return undef
            }

            # FAIL directive processed here after BLOCK directive fails if
            # no non-fatal directive is specified in the ruleset
            return
               (
                  $this->_throw
                     (
                        'bad lock',
                        {
                           'filename'  => $file,
                           'exception' => $!,
                        }
                     )
               );
         }
      }
      else {

         # ZERO directive processed here
         if ($policy->{'ZERO'}) { return 0 }

         # UNDEF directive processed here
         elsif ($policy->{'UNDEF'}) { return undef }

         # WARN directive processed here
         elsif ($policy->{'WARN'})  {

            $this->_throw
               (
                  'bad nblock',
                  {
                     'filename'  => $file,
                     'exception' => $!,
                  },
                  '--as-warning',
               );

            return undef
         }

         # FAIL directive processed here after previous directive(s) fail,
         # or no non-fatal directive is specified in the ruleset
         return
            (
               $this->_throw
                  (
                     'bad nblock',
                     {
                        'filename'  => $file,
                        'exception' => $!,
                     }
                  )
            );
      }

      return undef
   }

   $fh;
}


# --------------------------------------------------------
# File::Util::_release()
# --------------------------------------------------------
sub _release {

   my($this,$fh) = @_;

   return($this->_throw('Not a filehandle.', {'arg' => $fh}))
      unless ($fh && ref(\$fh||'') eq 'GLOB');

   if ($CAN_FLOCK) { flock($fh, &Fcntl::LOCK_UN) } 1;
}


# --------------------------------------------------------
# File::Util::valid_filename()
# --------------------------------------------------------
sub valid_filename { my($f) = myargs(@_); $f !~ /$ILLEGAL_CHR/ }


# --------------------------------------------------------
# File::Util::strip_path()
# --------------------------------------------------------
sub strip_path { my($f) = myargs(@_); pop @{['', split(/$DIRSPLIT/,$f)]}||'' }


# --------------------------------------------------------
# File::Util::line_count()
# --------------------------------------------------------
sub line_count {

   my($this,$file) = @_; my($buff) = ''; my($lines) = 0; my($cmd) = '<' . $file;

   local(*LINES);

   open(LINES, $file) or
      return
         (
            $this->_throw
               (
                  'bad open',
                  {
                     'filename'  => $file,
                     'mode'      => 'read',
                     'exception' => $!,
                     'cmd'       => $cmd,
                  }
               )
         );

   while (sysread(LINES, $buff, 4096)) {

      $lines += eval('$buff =~ tr/' . $NL . '//'); $buff  = '';
   }

   close(LINES); $lines;
}


# --------------------------------------------------------
# File::Util::DESTROY(), end File::Util class definition
# --------------------------------------------------------
sub DESTROY {}
1;

__END__

# --------------------------------------------------------
# File::Util::bitmask()
# --------------------------------------------------------
sub bitmask {

   my($f) = myargs(@_);

   unless (defined($f) and length($f)) {

      return(q[No input filename was provided.]);
   }

   return(qq[No such file or directory as "$f"]) unless (-e $f);

   sprintf('%04o',(stat($f))[2] & 0777);
}


# --------------------------------------------------------
# File::Util::can_flock()
# --------------------------------------------------------
sub can_flock { $CAN_FLOCK }


# --------------------------------------------------------
# File::Util::created()
# --------------------------------------------------------
sub created {

   my($f) = myargs(@_); $f ||= '';

   return undef unless -e $f;

   $^T - ((-M $f) * 60 * 60 * 24)
}


# --------------------------------------------------------
# File::Util::ebcdic()
# --------------------------------------------------------
sub ebcdic { $EBCDIC }


# --------------------------------------------------------
# File::Util::escape_filename()
# --------------------------------------------------------
sub escape_filename {

   my($opts)   = shave_opts(\@_);
   my($file,$escape,$also) = myargs(@_);
   my(@dirs)   = ();
   my($path)   = '';
   my($mskpath)= '';

   $escape  = '_' if (!defined($escape));

   # take care of idiots  HEY!  I resent that!
   $file =~ s/$DIRSPLIT$//;

   # determine existance of the file path, make directory(ies) for the
   # path if the full directory path doesn't exist
   @dirs = split(/$DIRSPLIT/, $file);

   if (scalar(@dirs) > 0) {

      $file    = pop(@dirs);
      $path    = join($SL, @dirs);
      $mskpath = join($escape , @dirs);
   }

   if (length($path) > 0) {

      $path = '.' . $SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
   }
   else { $path = '.'; }

   if ($also) { $file =~ s/\Q$also\E/$escape/g; }
   $file =~ s/$ILLEGAL_CHR/$escape/g;
   $file =~ s/^(?:\.$DIRSPLIT)+?\w//o;

   if ($opts->{'--strip-path'}) {

      # take care of relative path prefixes still present
      $file =~ s/^(?:\.$DIRSPLIT)+?//o;

      return($file);
   }

   $mskpath . $escape . $file;
}


# --------------------------------------------------------
# File::Util::existent()
# --------------------------------------------------------
sub existent { my($f) = myargs(@_); -e $f }


# --------------------------------------------------------
# File::Util::file_type()
# --------------------------------------------------------
sub file_type {

   my($f) = myargs(@_);

   unless (defined($f) and length($f)) {

      return(q[No input filename was provided.]);
   }

   return(qq[No such file or directory as "$f"]) unless (-e $f);

   my(@ret) = ();

   push @ret, 'plain'     if (-f $f);   push @ret, 'text'      if (-T $f);
   push @ret, 'binary'    if (-B $f);   push @ret, 'directory' if (-d $f);
   push @ret, 'symlink'   if (-l $f);   push @ret, 'pipe'      if (-p $f);
   push @ret, 'socket'    if (-S $f);   push @ret, 'block'     if (-b $f);
   push @ret, 'character' if (-c $f);   push @ret, 'tty'       if (-t $f);

   push(@ret,'cannot determine file type') unless @ret; @ret
}


# --------------------------------------------------------
# File::Util::flock_rules()
# --------------------------------------------------------
sub flock_rules {

   my($arg) = myargs(@_);

   if (defined($arg)) { @ONLOCKFAIL = myargs(@_) }

   @ONLOCKFAIL
}


# --------------------------------------------------------
# File::Util::isbin()
# --------------------------------------------------------
sub isbin { my($f) = myargs(@_); -B $f }


# --------------------------------------------------------
# File::Util::last_access()
# --------------------------------------------------------
sub last_access {

   my($f) = myargs(@_); $f ||= '';

   return undef unless -e $f;

   # return the last accessed time of $f
   $^T - ((-A $f) * 60 * 60 * 24)
}


# --------------------------------------------------------
# File::Util::last_mod()
# --------------------------------------------------------
sub last_mod {

   my($f) = myargs(@_); $f ||= '';

   return undef unless -e $f;

   $^T - ((-C $f) * 60 * 60 * 24)
}


# --------------------------------------------------------
# File::Util::load_dir()
# --------------------------------------------------------
sub load_dir {

   my($this) = shift(@_); my($opts) = $this->shave_opts(\@_);
   my($dir)  = shift(@_)||''; my(@files) = ();
   my($dir_hash) = {}; my($dir_list) = [];

   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'load_dir',
                  'missing'   => 'a directory name',
                  'opts'      => $opts,
               }
            )
      )
         unless length($dir);

   @files = $this->list_dir($dir,'--files-only');

   # map the content of each file into a hash key-value element where the
   # key name for each file is the name of the file
   if (!$opts->{'--as-list'} and !$opts->{'--as-listref'}) {

      foreach (@files) {

         $dir_hash->{ $_ } = $this->load_file( $dir . $SL . $_ );
      }

      return($dir_hash);
   }
   else {

      foreach (@files) {

         push(@{$dir_list},$this->load_file( $dir . $SL . $_ ));
      }

      return($dir_list) if ($opts->{'--as-listref'}); return(@{$dir_list});
   }

   $dir_hash;
}


# --------------------------------------------------------
# File::Util::make_dir()
# --------------------------------------------------------
sub make_dir {

   my($this,$dir,$bitmask) = @_;

   # if the call to this method didn't include a directory name to create,
   # then complain about it
   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'make_dir',
                  'missing'   => 'a directory name',
               }
            )
      )
         unless (length($dir) > 0);

   # if prospective directory name contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return
      (
         $this->_throw
            (
               'bad chars',
               {
                  'string'    => $dir,
                  'purpose'   => 'the name of a directory',
               }
            )
      )
         if ($dir =~ /$DIRSPLIT{2,}/);

   $bitmask ||= 0777; if (length($bitmask) == 3) {$bitmask = '0' . $bitmask}

   $dir =~ s/$DIRSPLIT$//;

   my(@dirs_in_path) = split(/$DIRSPLIT/,$dir);
   my(@substitute)   = @dirs_in_path;

   foreach (@dirs_in_path) {

      # if prospective directory name contains illegal chars then complain
      return
         (
            $this->_throw
               (
                  'bad chars',
                  {
                     'string'    => $_,
                     'purpose'   => 'the name of a directory',
                  }
               )
         )
            if (!$this->valid_filename($_))
   }

   my($depth) = 0;

   foreach (@substitute) {

      ++$depth; last if ($depth == scalar(@dirs_in_path));

      $dirs_in_path[$depth] ||= '.';

      $dirs_in_path[$depth] =
         join
            (
               $SL,
               @dirs_in_path[($depth-1)..$depth]
            );
   }

   my($i) = 0;

   foreach (@dirs_in_path) {

      my($dir) = $_; my($up) = ($i > 0) ? $dirs_in_path[$i-1] : '..';

      ++$i;

      if (-e $dir and !-d $dir) {

         return
            (
               $this->_throw
                  (
                     'called mkdir on a file',
                     {
                        'filename'  => $dir,
                        'dirname'   => $up . $SL,
                     }
                  )
            );
      }

      next if -e $dir;

      # it's good to know beforehand whether or not we have permission to
      # create dirs here, which allows us to handle such an exception
      # before it handles us.
      return
         (
            $this->_throw
               (
                  'cant dcreate',
                  {
                     'filename'  => $dir,
                     'dirname'   => $up . $SL,
                  }
               )
         )
            unless ($this->can_write($up));

      mkdir($dir, $bitmask) or
         return
            (
               $this->_throw
                  (
                     'bad make_dir',
                     {
                        'exception' => $!,
                        'dir'       => $dir,
                        'bitmask'   => $bitmask,
                     }
                  )
            );
   }

   $dir;
}


# --------------------------------------------------------
# File::Util::max_dives()
# --------------------------------------------------------
sub max_dives {

   my($arg) = myargs(@_);

   if (defined($arg)) { $MAXDIVES = $arg }

   $MAXDIVES
}


# --------------------------------------------------------
# File::Util::needs_binmode()
# --------------------------------------------------------
sub needs_binmode { $NEEDS_BINMODE }


# --------------------------------------------------------
# File::Util::open_handle()
# --------------------------------------------------------
sub open_handle {

   my($this)      = shift(@_);
   my($opts)      = $this->shave_opts(\@_);
   my($in)        = $this->coerce_array(@_);
   my($filename)  = $in->{'file'}      || '';
   my($mode)      = $in->{'mode'}      || 'write';
   my($bitmask)   = $in->{'bitmask'}   || 0777;
   my($fh)        = undef;
   my($path)      = '';
   my(@dirs)      = ();

   $filename ||= $$in{'filename'}; $filename ||= ''; $path = $filename;

   # if the call to this method didn't include a filename to which the caller
   # wants us to write, then complain about it
   return
      (
         $this->_throw
            (
               'no input',
               {
                  'meth'      => 'write_file',
                  'missing'   => 'a file name to create, write, or append',
                  'opts'      => $opts,
               }
            )
      )
         unless length($filename);

   # if prospective filename contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return
      (
         $this->_throw
            (
               'bad chars',
               {
                  'string'    => $filename,
                  'purpose'   => 'the name of a file or directory',
                  'opts'      => $opts,
               }
            )
      )
         if ($filename =~ /(?:$DIRSPLIT){2,}/);

   # take care of idiots.  HEY!  I resent that!
   $filename =~ s/$DIRSPLIT$//;

   # determine existance of the file path, make directory(ies) for the
   # path if the full directory path doesn't exist
   @dirs = split(/$DIRSPLIT/, $filename);

   # if prospective file name has illegal chars then complain
   foreach (@dirs) {

      return
         (
            $this->_throw
               (
                  'bad chars',
                  {
                     'string'    => $_,
                     'purpose'   => 'the name of a file or directory',
                     'opts'      => $opts,
                  }
               )
         )
            if (!$this->valid_filename($_));
   }

   if (scalar(@dirs) > 0) {

      $filename = pop(@dirs); $path = join($SL, @dirs);
   }

   if (length($path) > 0) {

      $path = '.' . $SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
   }
   else { $path = '.'; }

   if (!(-e $path)) { $this->make_dir($path, $bitmask); }

   my($openarg) = qq[$path$SL$filename];


   if ($mode eq 'write' or $mode eq 'append') {

      # Check whether or not we have permission to open and perform writes
      # on this file.

      if (-e $openarg) {

         return
            (
               $this->_throw
                  (
                     'cant fwrite',
                     {
                        'filename'  => $openarg,
                        'dirname'   => $path . $SL,
                        'opts'      => $opts,
                     }
                  )
            )
               unless ($this->can_write($openarg));
      }
      else {

         # If file doesn't exist and the path isn't writable, the error is
         # one of unallowed creation.
         return
            (
               $this->_throw
                  (
                     'cant fcreate',
                     {
                        'filename'  => $openarg,
                        'dirname'   => $path . $SL,
                        'opts'      => $opts,
                     }
                  )
            )
               unless ($this->can_write($path . $SL));
      }
   }
   elsif ($mode eq 'read') {

      # Check whether or not we have permission to open and perform reads
      # on this file, starting with file's housing directory.

      return
         (
            $this->_throw
               (
                  'cant dread',
                  {
                     'filename'  => $path . $SL . $filename,
                     'dirname'   => $path . $SL,
                     'opts'      => $opts,
                  }
               )
         )
            unless ($this->can_read($path . $SL));

      # Check the readability of the file itself
      return
         (
            $this->_throw
               (
                  'cant fread',
                  {
                     'filename'  => $path . $SL . $filename,
                     'dirname'   => $path . $SL,
                     'opts'      => $opts,
                  }
               )
         )
            unless ($this->can_read($path . $SL . $filename));
   }
   else {

      return
         (
            $this->_throw
               (
                  'no input',
                  {
                     'meth'      => 'open_handle',
                     'missing'   => q[a valid IO mode. (eg- 'read', 'write'...],
                     'opts'      => $opts,
                  }
               )
         )
   }

   # we need a unique filehandle
   do { $fh = int(rand(time)) . $$; $fh = eval('*' . 'OPEN_TO_FH' . $fh) }
   while ( fileno($fh) );

   # if you use the '--no-lock' option you are probably stupid
   if ($$opts{'--no-lock'} || !$USE_FLOCK) {

      # get open mode
      $mode = $$MODES{'popen'}{ $mode };

      open($fh, $mode . $openarg) or
         return
            (
               $this->_throw
                  (
                     'bad open',
                     {
                        'filename'  => $openarg,
                        'mode'      => $mode,
                        'exception' => $!,
                        'cmd'       => $mode . $openarg,
                        'opts'      => $opts,
                     }
                  )
            );
   }
   else {

      # open read-only first to safely check if we can get a lock.
      if (-e $openarg) {

         open($fh, '<' . $openarg) or
            return
               (
                  $this->_throw
                     (
                        'bad open',
                        {
                           'filename'  => $openarg,
                           'mode'      => 'read',
                           'exception' => $!,
                           'cmd'       => $mode . $openarg,
                           'opts'      => $opts,
                        }
                     )
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, $fh);

         return($lockstat) unless $lockstat;

         if ($mode ne 'read') {

            open($fh, $$MODES{'popen'}{ $mode } . $openarg) or
               return
                  (
                     $this->_throw
                        (
                           'bad open',
                           {
                              'exception' => $!,
                              'filename'  => $openarg,
                              'mode'      => $mode,
                              'opts'      => $opts,
                              'cmd'       => $$MODES{'popen'}{ $mode }
                                          . $openarg,
                           }
                        )
                  );
         }
      }
      else {

         open($fh, $$MODES{'popen'}{ $mode } . $openarg) or
            return
               (
                  $this->_throw
                     (
                        'bad open',
                        {
                           'exception' => $!,
                           'filename'  => $openarg,
                           'mode'      => $mode,
                           'opts'      => $opts,
                           'cmd'       => $$MODES{'popen'}{ $mode }
                                       . $openarg,
                        }
                     )
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, $fh);

         return($lockstat) unless $lockstat;
      }
   }

   # return file handle reference to the caller
   $fh;
}


# --------------------------------------------------------
# File::Util::os()
# --------------------------------------------------------
sub os { $OS }


# --------------------------------------------------------
# File::Util::readlimit()
# --------------------------------------------------------
sub readlimit {

   my($arg) = myargs(@_);

   if (defined($arg)) { $READLIMIT = $arg }

   $READLIMIT
}


# --------------------------------------------------------
# File::Util::size()
# --------------------------------------------------------
sub size { my($f) = myargs(@_); $f ||= ''; return undef unless -e $f; -s $f }


# --------------------------------------------------------
# File::Util::trunc()
# --------------------------------------------------------
sub trunc { $_[0]->write_file('mode' => 'trunc', 'file' => $_[1]) }


# --------------------------------------------------------
# File::Util::use_flock()
# --------------------------------------------------------
sub use_flock {

   my($arg) = myargs(@_);

   if (defined($arg)) { $USE_FLOCK = $arg }

   $USE_FLOCK
}


# --------------------------------------------------------
# File::Util::_throw
# --------------------------------------------------------
sub _throw {

   my($this) = shift(@_); my($opts) = $this->shave_opts(\@_);

   return(0) if
      (
         $this->{'opts'}{'--fatals-as-status'}
            ||
         $this->{'fatals-as-status'}
      );

   $this->{'expt'}||={};

   unless (UNIVERSAL::isa($this->{'expt'},'Exception::Handler')) {

      require Exception::Handler; $this->{'expt'} = Exception::Handler->new();
   }

   my($error) = ''; my($in) = {};

   if (@_ == 1) {

      if (defined($_[0])) { $error = 'plain error'; goto PLAIN_ERRORS }
   }
   else { $error = shift(@_) || 'empty error' }

   $in = shift(@_)||{};

   map { $_ = defined($_) ? $_ : 'undefined value' } keys(%$in);

   PLAIN_ERRORS:

   my($bad_news) =
      CORE::eval
         (
            q[<<__ERRORBLOCK__]
            . &NL . &_errors($error)
            . &NL . q[__ERRORBLOCK__]
         );

   if ($opts->{'--as-warning'}) {

      warn($this->{'expt'}->trace(($@ || $bad_news))) and return()
   }
   elsif
      (
         $this->{'opts'}{'--fatals-as-errmsg'}
            ||
         $opts->{'--return'}
      )
   {
      return($this->{'expt'}->trace(($@ || $bad_news)))
   }
   elsif
      (
         $this->{'opts'}{'--fatals-as-status'}
            ||
         $opts->{'--return-status'}
      )
   { return undef } elsif ($this->{'opts'}{'--fatals-as-warning'}) {

      warn($this->{'expt'}->trace(($@ || $bad_news))) and return undef
   }

   foreach (keys(%{$in})) {

      next if ($_ eq 'opts');

      $bad_news .= qq[ARG   $_ = $in->{$_}] . $NL;
   }

   if ($in->{'opts'}) {

      foreach (keys(%{$$in{'opts'}})) {

         $_ = (defined($_)) ? $_  : 'empty value';

         $bad_news .= qq[OPT   $_] . $NL;
      }
   }

   warn($this->{'expt'}->trace(($@ || $bad_news))) if ($opts->{'--warn-also'});

   $this->{'expt'}->fail(($@ || $bad_news));

   '';
}


#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#
# ERROR MESSAGES
#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#%#
sub _errors {

   use vars qw($EBL $EBR);
   ($EBL,$EBR) = (chr(187), chr(171));
   ($EBL,$EBR) = ('{','}') if ($OS eq 'DOS');

   {
# NO SUCH FILE
'no such file' => <<'__bad_open__',
File::Util can't open
   $EBL$in->{'filename'}$EBR
because no such file or directory exists.

Origin:     This is *most likely* due to human error.
Solution:   Cannot diagnose.  A human must investigate the problem.
__bad_open__


# CAN'T READ FILE
'cant fread' => <<'__cant_read__',
Permissions conflict.  File::Util can't read the contents of this file:
   $EBL$in->{'filename'}$EBR

   Due to insufficient permissions, the system has denied Perl the right to
   view the contents of this file.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777 ]}$EBR

   The directory housing it has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with File::Util.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks File::Util to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_read__


# CAN'T CREATE FILE
'cant fcreate' => <<'__cant_write__',
Permissions conflict.  File::Util can't create this file:
   $EBL$in->{'filename'}$EBR

   File::Util can't create this file because the system has denied Perl
   the right to create files in the parent directory.

   The -e test returns $EBL@{[-e $in->{'dirname'} ]}$EBR for the directory.
   The -r test returns $EBL@{[-r $in->{'dirname'} ]}$EBR for the directory.
   The -R test returns $EBL@{[-R $in->{'dirname'} ]}$EBR for the directory.
   The -w test returns $EBL@{[-w $in->{'dirname'} ]}$EBR for the directory
   The -W test returns $EBL@{[-w $in->{'dirname'} ]}$EBR for the directory

   Parent directory: (path may be relative and/or redundant)
      $EBL$in->{'dirname'}$EBR

   Parent directory has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with File::Util.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks File::Util to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T WRITE TO FILE
'cant fwrite' => <<'__cant_write__',
Permissions conflict.  File::Util can't write to this file:
   $EBL$in->{'filename'}$EBR

   Due to insufficient permissions, the system has denied Perl the right
   to modify the contents of this file.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777) ]}$EBR

   Parent directory has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with File::Util.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks File::Util to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T LIST DIRECTORY
'cant dread' => <<'__cant_read__',
Permissions conflict.  File::Util can't list the contents of this directory:
   $EBL$in->{'dirname'}$EBR

   Due to insufficient permissions, the system has denied Perl the right to
   view the contents of this directory.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777) ]}$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with File::Util.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks File::Util to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_read__


# CAN'T CREATE DIRECTORY
'cant dcreate' => <<'__cant_write__',
Permissions conflict.  File::Util can't create:
   $EBL$in->{'filename'}$EBR

   File::Util can't create this directory because the system has denied
   Perl the right to create files in the parent directory.

   Parent directory: (path may be relative and/or redundant)
      $EBL$in->{'dirname'}$EBR

   Parent directory has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with File::Util.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks File::Util to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T OPEN
'bad open' => <<'__bad_open__',
File::Util can't open this file for $EBL$in->{'mode'}$EBR:
   $EBL$in->{'filename'}$EBR

   The system returned this error:
      $EBL$in->{'exception'}$EBR

   File::Util used this directive in its attempt to open the file
      $EBL$in->{'cmd'}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_open__


# BAD CLOSE
'bad close' => <<'__bad_close__',
File::Util couldn't close this file after $EBL$in->{'mode'}$EBR
   $EBL$in->{'filename'}$EBR

   The system returned this error:
      $EBL$in->{'exception'}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     Could be either human _or_ system error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_close__


# CAN'T TRUNCATE
'bad systrunc' => <<'__bad_systrunc__',
File::Util couldn't truncate() on $EBL$in->{'filename'}$EBR after having
successfully opened the file in write mode.

The system returned this error:
   $EBL$in->{'exception'}$EBR

Current flock_rules policy:
   $EBL@ONLOCKFAIL$EBR

This is most likely _not_ a human error, but has to do with your system's
support for the C truncate() function.
__bad_systrunc__


# CAN'T GET NON-BLOCKING FLOCK
'bad nblock' => <<'__bad_lock__',
File::Util can't get a non-blocking exclusive lock on the file
   $EBL$in->{'filename'}$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Current flock_rules policy:
   $EBL@ONLOCKFAIL$EBR

Origin:     Could be either human _or_ system error.
Solution:   Fall back to an attempt at getting a lock on the file by blocking.
            Investigate the reason why you can't get a lock on the file,
            it is usually because of improper programming which causes
            race conditions on one or more files.
__bad_lock__


# CAN'T GET FLOCK AFTER BLOCKING
'bad lock' => <<'__bad_lock__',
File::Util can't get a blocking exclusive lock on the file.
   $EBL$in->{'filename'}$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Current flock_rules policy:
   $EBL@ONLOCKFAIL$EBR

Origin:     Could be either human _or_ system error.
Solution:   Investigate the reason why you can't get a lock on the file,
            it is usually because of improper programming which causes
            race conditions on one or more files.
__bad_lock__


# CAN'T OPEN ON A DIRECTORY
'called open on a dir' => <<'__bad_open__',
File::Util can't call open() on this file because it is a directory
   $EBL$in->{'filename'}$EBR

Origin:     This is a human error.
Solution:   Use File::Util::load_file() to load the contents of a file
            Use File::Util::list_dir() to list the contents of a directory
__bad_open__


# CAN'T OPENDIR ON A FILE
'called opendir on a file' => <<'__bad_open__',
File::Util can't opendir() on this file because it is not a directory.
   $EBL$in->{'filename'}$EBR

Use File::Util::load_file() to load the contents of a file
Use File::Util::list_dir() to list the contents of a directory

Origin:     This is a human error.
Solution:   Use File::Util::load_file() to load the contents of a file
            Use File::Util::list_dir() to list the contents of a directory
__bad_open__


# CAN'T MKDIR ON A FILE
'called mkdir on a file' => <<'__bad_open__',
File::Util can't mkdir() for this path name because it already exists as a file.
   $EBL$in->{'filename'}$EBR

Origin:     This is a human error.
Solution:   Resolve naming issue between the existant file and the directory
            you wish to create.
__bad_open__


# PASSED READLIMIT
'readlimit exceeded' => <<'__readlimit__',
File::Util can't load file: $EBL$in->{'filename'}$EBR
into memory because its size exceeds the maximum file size allowed
for a read.

The size of this file is $EBL$in->{'size'}$EBR bytes.

Currently the read limit is set at $EBL$READLIMIT$EBR bytes.

Origin:     This is a human error.
Solution:   Consider setting the limit to a higher number of bytes.
__readlimit__


# BAD OPENDIR
'bad opendir' => <<'__bad_opendir__',
File::Util can't opendir this on $EBL$dir$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Origin:     Could be either human _or_ system error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_opendir__


# BAD MAKEDIR
'bad make_dir' => <<'__bad_make_dir__',
File::Util had a problem with the system while attempting to create the directory
you specified with a bitmask of $EBL$in->{'bitmask'}$EBR

directory: $EBL$in->{'dir'}$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Origin:     Could be either human _or_ system error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_make_dir__


# BAD CALL TO METHOD FOO
'no input' => <<'__no_input__',
File::Util can't honor your call to ${\$EBL}File::Util::$in->{'meth'}()$EBR
because you didn't provide $EBL@{[$in->{'missing'}||'the required input']}$EBR

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__no_input__


# PLAIN ERROR TYPE
'plain error' => <<'__plain_error__',
File::Util failed with the following message:
$_[0]
__plain_error__


# INVALID ERROR TYPE
'unknown error message' => <<'__foobar_input__',
File::Util failed with an invalid error-type designation.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__foobar_input__


# EMPTY ERROR TYPE
'empty error' => <<'__no_input__',
File::Util failed with an empty error-type designation.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__no_input__


# BAD CHARS
'bad chars' => <<'__bad_chars__',
File::Util can't use this string for $EBL$in->{'purpose'}$EBR.
   $EBL$in->{'string'}$EBR
It contains illegal characters.

Illegal characters are:
   \\   (backslash)
   /   (forward slash)
   :   (colon)
   |   (pipe)
   *   (asterisk)
   ?   (question mark)
   "   (double quote)
   <   (less than)
   >   (greater than)
   \\t  (tab)
   \\ck (vertical tabulator)
   \\r  (newline CR)
   \\n  (newline LF)

Origin:     This is a human error.
Solution:   A human must remove the illegal characters from this string.
__bad_chars__


# NOT A VALID FILEHANDLE
'not a FH' => <<'__bad_handle__',
File::Util can't unlock file with an invalid file handle reference:
   $EBL$fh$EBR is not a valid filehandle

Origin:     This is most likely an internal error within the File::Util module.
Solution:   A human must investigate the problem.  Send a usenet post with this
            error message in its entirety to usenet group:
            $EBL news:comp.lang.perl.modules $EBR
__bad_handle__

 'foo' => '' }->{ shift(@_) || 'foo' }
}

=pod

=head1 NAME

File::Util - Easy, versatile, portable file handling

=head1 IMPORTANT!

This is a developer's release, and is not intended for use in the public sector.
This code is made available for developers who wish to aid in the furthering of
the code, though B<it _is_ stable>.

This is I<not> a registered module in the CPAN module list.  It is not part of
the CPAN yet.

=head1 SYNOPSIS

   Nothing here at present.

=head1 DESCRIPTION

File::Util provides a comprehensive toolbox of utilities to automate all
kinds of common tasks on file / directories.  Its purpose is to do so
in the most portable manner possible so that users of this module won't
have to worry about whether their programs will work on other OSes
and machines.

=head1 INSTALLATION

To install this module type the following at the command prompt:

   perl Makefile.PL
   make
   make test
   make install

On windows machines use nmake rather than make; those running cygwin don't have
to worry about this.  If you don't know what cygwin is, use nmake and check out
<URL: http://cygwin.com/ > after you're done installing this module if you want
to find out.

=head1 File::Util ISA

=over

=item Exporter

=item Class::OOorNO

=back

=head1 METHODS

Item's marked with an asterisk (*) are AUTOLOAD-ed methods.  I<(see the
L<AutoLoader> documentation.)>  Item's marked with the dagger symbol (E<0206>)
are constant subroutines which take no argments and always return the same
value.

=over

=head2 bitmask( [file name] ) *

I<Documentation is under way.>

=head2 can_flock * E<0206>

I<Documentation is under way.>

=head2 can_read( [file name] )

I<Documentation is under way.>

=head2 can_write( [file name] )

I<Documentation is under way.>

=head2 created( [file name] ) *

I<Documentation is under way.>

=head2 ebcdic * E<0206>

I<Documentation is under way.>

=head2 escape_filename( [string] ) *

I<Documentation is under way.>

=head2 existent( [file name] ) *

I<Documentation is under way.>

=head2 file_type( [file name] ) *

I<Documentation is under way.>

=head2 flock_rules( [KEYWORDs] ) *

I<Documentation is under way.>

=head2 isbin( [file name] ) *

I<Documentation is under way.>

=head2 last_access( [file name] ) *

I<Documentation is under way.>

=head2 last_mod( [file name] ) *

I<Documentation is under way.>

=head2 line_count( [file name] )

I<Documentation is under way.>

=head2 list_dir( [directory name] , [--opts] )

I<Documentation is under way.>

=head2 load_dir( [directory name] , [--opts] ) *

I<Documentation is under way.>

=head2 load_file( [file name] , [--opts] )

I<Documentation is under way.>

=head2 make_dir( [new directory name] , [--opts] ) *

I<Documentation is under way.>

=head2 max_dives( [integer] ) *

I<Documentation is under way.>

=head2 needs_binmode * E<0206>

I<Documentation is under way.>

=head2 new( [--opts] )

I<Documentation is under way.>

=head2 open_handle( [file name] , [--opts] ) *

I<Documentation is under way.>

=head2 os * E<0206>

I<Documentation is under way.>

=head2 readlimit( [integer] ) *

I<Documentation is under way.>

=head2 size( [file name] ) *

I<Documentation is under way.>

=head2 strip_path( [string] )

I<Documentation is under way.>

=head2 trunc( [file name] ) *

I<Documentation is under way.>

=head2 use_flock( [true / false value] ) *

I<Documentation is under way.>

=head2 write_file('file' =>  [file name] , 'content' =>  [data] ,  [--opts])

I<Documentation is under way.>

=head2 valid_filename( [string] )

I<Documentation is under way.>

=head2 VERSION E<0206>

I<Documentation is under way.>

=head1 CONSTANTS

=head2 NL

I<Documentation is under way.>

=head2 SL

I<Documentation is under way.>

=head1 EXPORT

None by default.

=head1 EXPORT_OK

=over

=item L<bitmask()|/bitmask>

=item L<can_flock()|/can_flock>

=item L<can_read()|/can_read>

=item L<can_write()|/can_write>

=item L<ebcdic()|/ebcdic>

=item L<escape_filename()|/escape_filename>

=item L<existent()|/existent>

=item L<file_type()|/file_type>

=item L<isbin()|/isbin>

=item L<NL|/NL>

=item L<needs_binmode()|/needs_binmode>

=item L<os()|/os>

=item L<size()|/size>

=item L<SL|/SL>

=item L<strip_path()|/strip_path>

=item L<valid_filename()|/valid_filename>

=item Symbols in I<@Class::OOorNO::EXPORT_OK> are made available for import...

=back

=head2 EXPORT_TAGS

   :all (exports all of @File::Util::EXPORT_OK)

=head1 PREREQUISITES

=over

=item L<Perl|perl> 5.006 or better

=item L<Class::OOorNO>        v0.00_2 or better

=item L<Exception::Handler>   v1.00_0 or better

=back

=head1 EXAMPLES

None at present.

=head1 BUGS

This documentation isn't done yet, as you can see.  This is being rectified
as quickly as possible.  Please excercise caution if you choose to use this
code before it can be further documented for you.  Please excuse the
inconvenience.

=head1 AUTHOR

Tommy Butler <L<cpan@atrixnet.com|mailto:cpan@atrixnet.com>>

=head1 AUTHOR

Tommy Butler <L<cpan@atrixnet.com|mailto:cpan@atrixnet.com>>

=head1 COPYRIGHT

Copyright(c) 2001-2003, Tommy Butler.  All rights reserved.

=head1 LICENSE

This library is free software, you may redistribute and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=over

=item L<Class::OOorNO>

=item L<Exception::Handler>

=item L<File::Slurp>

=item L<Exporter>

=item L<AutoLoader>

=back

=cut
