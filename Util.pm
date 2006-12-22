package File::Util;
use 5.006;
use strict;
use vars qw(
   $VERSION   @ISA   @EXPORT_OK   %EXPORT_TAGS
   $OS   $MODES   $READLIMIT   $MAXDIVES   $EMPTY_WRITES_OK
   $USE_FLOCK   @ONLOCKFAIL   $ILLEGAL_CHR   $CAN_FLOCK
   $NEEDS_BINMODE   $EBCDIC   $DIRSPLIT   $SL   $NL   $_LOCKS
);
use Exporter;
use AutoLoader qw( AUTOLOAD );
use Class::OOorNO qw( :all );
$VERSION    = 3.15; # Fri Dec 22 14:12:45 CST 2006
@ISA        = qw( Exporter   Class::OOorNO );
@EXPORT_OK  = (
   @Class::OOorNO::EXPORT_OK, qw(
      can_flock   ebcdic   existent   isbin   bitmask   NL   SL
      strip_path   can_read   can_write   file_type   needs_binmode
      valid_filename   size   escape_filename   return_path
      created   last_access   last_modified
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

$EBCDIC = qq[\t] ne qq[\011] ? 1 : 0;
$NEEDS_BINMODE = $OS =~ /WINDOWS|DOS|OS2|MSWin/ ? 1 : 0;
$NL =
   $NEEDS_BINMODE ? qq[\015\012]
      : $EBCDIC || $OS eq 'VMS' ? qq[\n]
         : $OS eq 'MACINTOSH' ? qq[\015]
            : qq[\012];
$SL =
   { 'DOS' => '\\', 'EPOC'   => '/', 'MACINTOSH' => ':',
     'OS2' => '\\', 'UNIX'   => '/', 'WINDOWS'   => '\\',
     'VMS' => '/',  'CYGWIN' => '/', }->{ $OS }||'/';

$_LOCKS = {};

} BEGIN { use constant NL => $NL; use constant SL => $SL; }

$DIRSPLIT    = qr/[\\\/\:]/;
$ILLEGAL_CHR = qr/[\/\|$NL\r\n\t\013\*\"\?\<\:\>\\]/;

$READLIMIT  = 52428800; # set readlimit to a default of 50 megabytes
$MAXDIVES   = 1000;     # maximum depth for recursive list_dir calls

use Fcntl qw( );

{ local($@); eval <<'__canflock__'; $CAN_FLOCK = $@ ? 0 : 1; }
flock(STDOUT, &Fcntl::LOCK_SH);
flock(STDOUT, &Fcntl::LOCK_UN);
__canflock__

# try to use file locking, define flock race conditions policy
$USE_FLOCK = 1; @ONLOCKFAIL = qw( NOBLOCKEX FAIL );

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

   my($this)   = {}; bless($this, shift(@_));
   my($in)     = $this->coerce_array(@_);

   my($opts)   = $this->shave_opts(\@_); $this->{'opts'} = $opts || {};

   $USE_FLOCK  = $in->{'use_flock'} if exists $in->{'use_flock'};

   $READLIMIT  = $in->{'readlimit'}
      if defined $in->{'readlimit'}
      && $$in{'readlimit'} !~ /\D/;

   $MAXDIVES   = $in->{'max_dives'}
      if defined $in->{'max_dives'}
      && $$in{'max_dives'} !~ /\D/;

   return $this;
}


# --------------------------------------------------------
# File::Util::list_dir()
# --------------------------------------------------------
sub list_dir {

   my($this) = shift(@_);
   my($opts) = $this->shave_opts(\@_);
   my($dir)  = shift(@_)||'.';
   my($path) = $dir;
   my($maxd) = $opts->{'--max-dives'} || $MAXDIVES;
   my($r)    = 0;
   my(@dirs) = (); my(@files) = (); my(@items) = ();

   return
      $this->_throw
         (
            'no input',
            {
               'meth'      => 'list_dir',
               'missing'   => 'a directory name',
               'opts'      => $opts,
            }
         )
      unless length($dir);

   return($this->_throw('no such file', {'filename' => $dir})) unless -e $dir;

   # whack off any trailing directory separator
   unless (length($dir) == 1)
   { $dir =~ s/$DIRSPLIT$//o; $path =~ s/$DIRSPLIT$//o; }

   return
      $this->_throw
         (
            'called opendir on a file',
            {
               'filename'  => $dir,
               'opts'      => $opts,
            }
         )
      unless (-d $dir);

   # this directory recursion method keeps track of dives based on the parent
   # directory of $dir, rather than on $dir itself so that multiple
   # subdirectories within the same parent directory don't improperly increment
   # the number of dives made
   if ($opts->{'--recursing'}) {

      my($pdir) = $dir; $pdir =~ s/(^.*)$DIRSPLIT.*/$1/;

      $this->{'traversed'}{ $pdir } = $pdir;
   }
   else { $this->{'traversed'} = {} }

   if (scalar keys %{ $this->{'traversed'} } >= $maxd) {

      return $this->_throw
         (
            'maxdives exceeded',
            {
               'meth'      => 'list_dir',
               'maxdives'  => $maxd,
               'opts'      => $opts,
            }
         )
   }

   $r = 1 if ($opts->{'--follow'} || $opts->{'--recurse'});

   local(*DIR);

   opendir(DIR, $dir) or
      return
         $this->_throw
            (
               'bad opendir',
               {
                  'dir'       => $dir,
                  'exception' => $!,
                  'opts'      => $opts,
               }
            );

   # read from beginning of the directory (doesn't seem necessary on any
   # platforms I've run code on, but just in case...)
   rewinddir(DIR);

   @files =
      exists($opts->{'--pattern'})
      ? grep(/$opts->{'--pattern'}/, readdir(DIR))
      : readdir(DIR);

   closedir(DIR) or
      return
         $this->_throw
            (
               'close dir',
               {
                  'dir'       => $dir,
                  'exception' => $!,
                  'opts'      => $opts,
               }
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
            ? $path . SL . $files[$i]
            : $files[$i];

      if (-d $path . SL . $files[$i]) { push(@dirs, $listing) }
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
               '--no-fsdots',    '--max-dives=' . $maxd
            );

         push(@dirs,@{$lsts[0]}); push(@items,@{$lsts[1]});
      }
   }

   if ($opts->{'--sl-after-dirs'}) {

      @dirs       = $this->_dropdots(@dirs,'--save-dots');
      my($dots)   = shift(@dirs);
      @dirs       = map ( ($_ .= SL), @dirs );
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

   return(scalar(@$reta))
      if $opts->{'--dirs-only'} && $opts->{'--count-only'};

   return(scalar(@$retb))
      if $opts->{'--files-only'} && $opts->{'--count-only'};

   return(scalar(@$reta) + scalar(@$retb)) if $opts->{'--count-only'};

   return($reta,$retb) if $opts->{'--as-ref'};

   $reta=[$reta] if $opts->{'--dirs-as-ref'};
   $retb=[$retb] if $opts->{'--files-as-ref'};

   return(@$reta) if $opts->{'--dirs-only'};
   return(@$retb) if $opts->{'--files-only'};

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

         $file = pop(@dirs); $path = join(SL, @dirs);
      }

      if (length($path) > 0) {

         $path = '.' . SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
      }
      else { $path = '.'; }

      return $this->_throw
         (
            'no input',
            {
               'meth'      => 'load_file',
               'missing'   => 'a file name or file handle reference',
               'opts'      => $opts,
            }
         )
      if (length($path . SL . $file) == 0);
   }
   else {

      $fh = $in->{'FH'}||''; $FHstatus = $in->{'FH_status'}||'';

      # did we get a filehandle?
      if (length($fh) > 0) { $FH_passed = 1; } else {

         return $this->_throw
            (
               'no input',
               {
                  'meth'      => 'load_file',
                  'missing'   => 'a file name or file handle reference',
                  'opts'      => $opts,
               }
            );
      }
   }

   if ($FH_passed) {

      my($buff) = 0; my($bytes_read) = 0;

      while (<$fh>) {

         if ($buff < $READLIMIT) {

            $bytes_read = read($fh,$content,$blocksize); $buff += $bytes_read;
         }
         else {

            return $this->_throw
               (
                  'readlimit exceeded',
                  {
                     'filename'  => '<FH>',
                     'size'      => qq[[truncated at $bytes_read]],
                     'opts'      => $opts,
                  }
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
   return $this->_throw
      (
         'no such file',
         {
            'filename'  => $path . SL . $file,
            'opts'      => $opts,
         }
      )
   unless -e $path . SL . $file;

   # it's good to know beforehand whether or not we have permission to open
   # and read from this file allowing us to handle such an exception before
   # it handles us.

   # first check the readability of the file's housing dir
   return $this->_throw
      (
         'cant dread',
         {
            'filename'  => $path . SL . $file,
            'dirname'   => $path . SL,
            'opts'      => $opts,
         }
      )
   unless (-r $path . SL);

   # now check the readability of the file itself
   return $this->_throw
      (
         'cant fread',
         {
            'filename'  => $path . SL . $file,
            'dirname'   => $path . SL,
            'opts'      => $opts,
         }
      )
   unless (-r $path . SL . $file);

   # if the file is a directory it will not be opened
   return $this->_throw
      (
         'called open on a dir',
         {
            'filename'  => $path . SL . $file,
            'opts'      => $opts,
         }
      )
   if -d $path . SL . $file;

   my($fsize) = -s $path . SL . $file;

   return $this->_throw
      (
         'readlimit exceeded',
         {
            'filename'  => $path . SL . $file,
            'size'      => $fsize,
            'opts'      => $opts,
         }
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
   my($cmd) = '<' . $path . SL . $file;

   # lock file before I/O on platforms that support it
   if ($$opts{'--no-lock'} || $$this{'opts'}{'--no-lock'}) {

      # if you use the '--no-lock' option you are probably inefficient
      open($fh, $cmd) or
         return $this->_throw
            (
               'bad open',
               {
                  'filename'  => $path . SL . $file,
                  'mode'      => $mode,
                  'exception' => $!,
                  'cmd'       => $cmd,
                  'opts'      => $opts,
               }
            );
   }
   else {

      open($fh, $cmd) or
         return $this->_throw
            (
               'bad open',
               {
                  'filename'  => $path . SL . $file,
                  'mode'      => $mode,
                  'exception' => $!,
                  'cmd'       => $cmd,
                  'opts'      => $opts,
               }
            );

      $this->_seize($path . SL . $file, $fh);
   }

   # call binmode on binary files for portability accross platforms such
   # as MS flavor OS family
   CORE::binmode($fh) if (-B $path . SL . $file);

   # assign the content of the file to this lexically scoped scalar variable
   # (memory for *that* variable will be freed when execution leaves this
   # method / sub
   $content = <$fh>;

   if ($$opts{'--no-lock'} || $$this{'opts'}{'--no-lock'}) {

      # if execution gets here, you used the '--no-lock' option, and you
      # are probably inefficient
      close($fh) or
         return $this->_throw
            (
               'bad close',
               {
                  'filename'  => $path . SL . $file,
                  'mode'      => $mode,
                  'exception' => $!,
                  'opts'      => $opts,
               }
            );
   }
   else {

      # release shadow-ed locks on the file
      $this->_release($fh);

      close($fh) or
         return $this->_throw
            (
               'bad close',
               {
                  'filename'  => $path . SL . $file,
                  'mode'      => $mode,
                  'exception' => $!,
                  'opts'      => $opts,
               }
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
   return $this->_throw
      (
         'no input',
         {
            'meth'      => 'write_file',
            'missing'   => 'a file name to create, write, or append',
            'opts'      => $opts,
         }
      )
   unless length($filename);

   # if prospective filename contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return $this->_throw
      (
         'bad chars',
         {
            'string'    => $filename,
            'purpose'   => 'the name of a file or directory',
            'opts'      => $opts,
         }
      )
   if ($filename =~ /(?:$DIRSPLIT){2,}/);

   # if the call to this method didn't include any data which the caller
   # wants us to write or append to the file, then complain about it
   return $this->_throw
      (
         'no input',
         {
            'meth'      => 'write_file',
            'missing'   => 'the content you want to write or append',
            'opts'      => $opts,
         }
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

   # remove trailing directory seperator
   $filename =~ s/$DIRSPLIT$//;

   # determine existance of the file path, make directory(ies) for the
   # path if the full directory path doesn't exist
   @dirs = split(/$DIRSPLIT/, $filename);

   # if prospective file name has illegal chars then complain
   foreach (@dirs) {

      return $this->_throw
         (
            'bad chars',
            {
               'string'    => $_,
               'purpose'   => 'the name of a file or directory',
               'opts'      => $opts,
            }
         )
      if (!$this->valid_filename($_));
   }

   if (scalar(@dirs) > 0) {

      $filename = pop(@dirs); $path = join(SL, @dirs);
   }

   if (length($path) > 0) {

      $path = '.' . SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
   }
   else { $path = '.'; }

   if (!(-e $path)) { $this->make_dir($path, $bitmask); }

   my($openarg) = qq[$path$SL$filename];

   if (-e $openarg) {

      return $this->_throw
         (
            'cant fwrite',
            {
               'filename'  => $openarg,
               'dirname'   => $path . SL,
               'opts'      => $opts,
            }
         )
      unless (-w $openarg);
   }
   else {

      # if file doesn't exist, the error is one of creation
      return $this->_throw
         (
            'cant fcreate',
            {
               'filename'  => $openarg,
               'dirname'   => $path . SL,
               'opts'      => $opts,
            }
         )
      unless (-w $path . SL);
   }

   if ($$opts{'--no-lock'} || !$USE_FLOCK) {

      # get open mode
      $mode = $$MODES{'popen'}{ $mode };

      # if you use the '--no-lock' option you are probably inefficient
      open(WRITE_FILE, $mode . $openarg) or
         return $this->_throw
            (
               'bad open',
               {
                  'filename'  => $openarg,
                  'mode'      => $mode,
                  'exception' => $!,
                  'cmd'       => $mode . $openarg,
                  'opts'      => $opts,
               }
            );
   }
   else {

      # open read-only first to safely check if we can get a lock.
      if (-e $openarg) {

         open(WRITE_FILE, '<' . $openarg) or
            return $this->_throw
               (
                  'bad open',
                  {
                     'filename'  => $openarg,
                     'mode'      => 'read',
                     'exception' => $!,
                     'cmd'       => $mode . $openarg,
                     'opts'      => $opts,
                  }
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, *WRITE_FILE);

         return($lockstat) unless $lockstat;

         sysopen(WRITE_FILE, $openarg, eval($$MODES{'sysopen'}{ $mode }))
            or return $this->_throw
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
               );
      }
      else {

         sysopen(WRITE_FILE, $openarg, eval($$MODES{'sysopen'}{ $mode }))
            or return $this->_throw
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
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, *WRITE_FILE);

         return($lockstat) unless $lockstat;
      }

      # now truncate
      if ($mode ne 'append') {

         truncate(WRITE_FILE,0) or
            return $this->_throw
               (
                  'bad systrunc',
                  {
                     'filename'  => $openarg,
                     'exception' => $!,
                     'opts'      => $opts,
                  }
               );
      }
   }

   $in->{'content'}||=''; syswrite(WRITE_FILE, $in->{'content'});

   $in->{'content'} = 1 if $mode eq 'trunc';

   # release lock on the file
   unless ($$opts{'--no-lock'} || !$USE_FLOCK) { $this->_release(*WRITE_FILE) }

   close(WRITE_FILE) or
      return $this->_throw
         (
            'bad close',
            {
               'filename'  => $openarg,
               'mode'      => $mode,
               'exception' => $!,
               'opts'      => $opts,
            }
         );

   return($in->{'content'});
}


# --------------------------------------------------------
# %$File::Util::LOCKS
# --------------------------------------------------------
$_LOCKS->{'IGNORE'}  = sub { $_[2] };
$_LOCKS->{'ZERO'}    = sub { 0 };
$_LOCKS->{'UNDEF'}   = sub { undef };
$_LOCKS->{'NOBLOCKEX'} = sub {
   return $_[2] if flock($_[2], &Fcntl::LOCK_EX | &Fcntl::LOCK_NB); undef
};
$_LOCKS->{'NOBLOCKSH'} = sub {
   return $_[2] if flock($_[2], &Fcntl::LOCK_SH | &Fcntl::LOCK_NB); undef
};
$_LOCKS->{'BLOCKEX'} = sub {
   return $_[2] if flock($_[2], &Fcntl::LOCK_EX); undef
};
$_LOCKS->{'BLOCKSH'} = sub {
   return $_[2] if flock($_[2], &Fcntl::LOCK_SH); undef
};
$_LOCKS->{'WARN'} = sub {
   $_[0]->_throw(
      'bad flock',
      {
         'filename'  => $_[1],
         'exception' => $!,
      },
      '--as-warning',
   ); undef
};


# --------------------------------------------------------
# File::Util::_seize()
# --------------------------------------------------------
sub _seize {

   my($this)   = shift(@_); my($file) = shift(@_)||''; my($fh) = shift(@_)||'';
   my(@policy) = @ONLOCKFAIL;
   my($policy) = {};

   # seize filehandle, return it if lock is successful

   # forget seizing if system can't flock
   return($fh) if !$CAN_FLOCK;

   return($this->_throw(q[no file name passed to _seize.])) unless $file;
   return($this->_throw(q[no handle passed to _seize.]))    unless $fh;

   while (@policy) {
      my($fh) = &{ $_LOCKS->{ shift @policy } }($this,$file,$fh);
      return $fh if ($fh || !scalar @policy)
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
sub valid_filename {

   my($f) = myargs(@_);

   $f !~ /$ILLEGAL_CHR/ ? 1 : undef
}


# --------------------------------------------------------
# File::Util::strip_path()
# --------------------------------------------------------
sub strip_path { my($f) = myargs(@_); pop @{['', split(/$DIRSPLIT/,$f)]}||'' }


# --------------------------------------------------------
# File::Util::line_count()
# --------------------------------------------------------
sub line_count {

   my($this,$file) = @_;
   my($buff)   = '';
   my($lines)  = 0;
   my($cmd)    = '<' . $file;

   local(*LINES);

   open(LINES, $file) or
      return $this->_throw
         (
            'bad open',
            {
               'filename'  => $file,
               'mode'      => 'read',
               'exception' => $!,
               'cmd'       => $cmd,
            }
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

   defined $f and -e $f ? sprintf('%04o',(stat($f))[2] & 0777) : undef
}


# --------------------------------------------------------
# File::Util::can_flock()
# --------------------------------------------------------
sub can_flock { $CAN_FLOCK }


# File::Util::--------------------------------------------
#   can_read(),   can_write()
# --------------------------------------------------------
sub can_read  { my($f) = myargs(@_); defined $f ? -r $f : undef }
sub can_write { my($f) = myargs(@_); defined $f ? -w $f : undef }


# --------------------------------------------------------
# File::Util::created()
# --------------------------------------------------------
sub created {

   my($f) = myargs(@_);

   defined $f and -e $f ? $^T - ((-M $f) * 60 * 60 * 24) : undef
}


# --------------------------------------------------------
# File::Util::ebcdic()
# --------------------------------------------------------
sub ebcdic { $EBCDIC }


# --------------------------------------------------------
# File::Util::escape_filename()
# --------------------------------------------------------
sub escape_filename {

   my($opts) = shave_opts(\@_);
   my($file,$escape,$also) = myargs(@_);

   return '' unless defined $file;

   $escape = '_' if !defined($escape);

   $file = strip_path($file) if $opts->{'--strip-path'};

   if ($also) { $file =~ s/\Q$also\E/$escape/g }

   $file =~ s/$ILLEGAL_CHR/$escape/g;
   $file =~ s/$DIRSPLIT/$escape/g;

   $file
}


# --------------------------------------------------------
# File::Util::existent()
# --------------------------------------------------------
sub existent { my($f) = myargs(@_); defined $f ? -e $f : undef }


# --------------------------------------------------------
# File::Util::file_type()
# --------------------------------------------------------
sub file_type {

   my($f) = myargs(@_);

   return undef unless defined $f and -e $f;

   my(@ret) = ();

   push @ret, 'PLAIN'     if (-f $f);   push @ret, 'TEXT'      if (-T $f);
   push @ret, 'BINARY'    if (-B $f);   push @ret, 'DIRECTORY' if (-d $f);
   push @ret, 'SYMLINK'   if (-l $f);   push @ret, 'PIPE'      if (-p $f);
   push @ret, 'SOCKET'    if (-S $f);   push @ret, 'BLOCK'     if (-b $f);
   push @ret, 'CHARACTER' if (-c $f);   push @ret, 'TTY'       if (-t $f);

   push(@ret,'Error: cannot determine file type') unless @ret; @ret
}


# --------------------------------------------------------
# File::Util::flock_rules()
# --------------------------------------------------------
sub flock_rules {

   my($this)   = shift(@_);
   my(@rules)  = myargs(@_);

   return @ONLOCKFAIL unless defined scalar @rules;

   my(%valid) = qw/
      NOBLOCKEX   NOBLOCKEX
      NOBLOCKSH   NOBLOCKSH
      BLOCKEX     BLOCKEX
      BLOCKSH     BLOCKSH
      FAIL        FAIL
      WARN        WARN
      IGNORE      IGNORE
      UNDEF       UNDEF
      ZERO        ZERO /;

   map {
      return $this->_throw('bad flock rules', { 'bad' => $_, 'all' => \@rules })
      unless exists $valid{ $_ }
   } @rules;

   @ONLOCKFAIL = @rules;

   @ONLOCKFAIL
}


# --------------------------------------------------------
# File::Util::isbin()
# --------------------------------------------------------
sub isbin { my($f) = myargs(@_); defined $f ? -B $f : undef }


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
# File::Util::last_modified()
# --------------------------------------------------------
sub last_modified {

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

   return $this->_throw
      (
         'no input',
         {
            'meth'      => 'load_dir',
            'missing'   => 'a directory name',
            'opts'      => $opts,
         }
      )
   unless length($dir);

   @files = $this->list_dir($dir,'--files-only');

   # map the content of each file into a hash key-value element where the
   # key name for each file is the name of the file
   if (!$opts->{'--as-list'} and !$opts->{'--as-listref'}) {

      foreach (@files) {

         $dir_hash->{ $_ } = $this->load_file( $dir . SL . $_ );
      }

      return($dir_hash);
   }
   else {

      foreach (@files) {

         push(@{$dir_list},$this->load_file( $dir . SL . $_ ));
      }

      return($dir_list) if ($opts->{'--as-listref'}); return(@{$dir_list});
   }

   $dir_hash;
}


# --------------------------------------------------------
# File::Util::make_dir()
# --------------------------------------------------------
sub make_dir {

   my($this) = shift(@_);
	my($opts) = $this->shave_opts(\@_);
	my($dir,$bitmask) = @_;

	if ($$opts{'--if-not-exists'}) {
		if (-e $dir) {
			if (-d $dir) {
				return $dir
			}
			else {
				return $this->_throw
					(
						'called mkdir on a file',
						{
							'filename'  => $dir,
							'dirname'   => join(SL,(split(SL,$dir))[0 .. -1]) . SL
						}
					);

			}
		}
		
	}

   # if the call to this method didn't include a directory name to create,
   # then complain about it
   return $this->_throw
      (
         'no input',
         {
            'meth'      => 'make_dir',
            'missing'   => 'a directory name',
         }
      )
   unless (defined($dir) && length($dir));

   # if prospective directory name contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return $this->_throw
      (
         'bad chars',
         {
            'string'    => $dir,
            'purpose'   => 'the name of a directory',
         }
      )
   if ($dir =~ /$DIRSPLIT{2,}/);

   $bitmask ||= 0777; if (length($bitmask) == 3) {$bitmask = '0' . $bitmask}

   $dir =~ s/$DIRSPLIT$//;

   my(@dirs_in_path) = split(/$DIRSPLIT/,$dir);
   my(@substitute)   = @dirs_in_path;

   foreach (@dirs_in_path) {

      # if prospective directory name contains illegal chars then complain
      return $this->_throw
         (
            'bad chars',
            {
               'string'    => $_,
               'purpose'   => 'the name of a directory',
            }
         )
      if (!$this->valid_filename($_))
   }

   my($depth) = 0;

   foreach (@substitute) {

      ++$depth; last if ($depth == scalar(@dirs_in_path));

      $dirs_in_path[$depth] ||= '.';

      $dirs_in_path[$depth] = join(SL, @dirs_in_path[($depth-1)..$depth]);
   }

   my($i) = 0;

   foreach (@dirs_in_path) {

      my($dir) = $_; my($up) = ($i > 0) ? $dirs_in_path[$i-1] : '..';

      ++$i;

      if (-e $dir and !-d $dir) {

         return $this->_throw
            (
               'called mkdir on a file',
               {
                  'filename'  => $dir,
                  'dirname'   => $up . SL,
               }
            );
      }

      next if -e $dir;

      # it's good to know beforehand whether or not we have permission to
      # create dirs here, which allows us to handle such an exception
      # before it handles us.
      return $this->_throw
         (
            'cant dcreate',
            {
               'filename'  => $dir,
               'dirname'   => $up . SL,
            }
         )
      unless (-w $up);

      mkdir($dir, $bitmask) or
         return $this->_throw
            (
               'bad make_dir',
               {
                  'exception' => $!,
                  'dir'       => $dir,
                  'bitmask'   => $bitmask,
               }
            );
   }

   $dir;
}


# --------------------------------------------------------
# File::Util::max_dives()
# --------------------------------------------------------
sub max_dives {

   my($arg) = myargs(@_);

   if (defined($arg)) {
      return $this->_throw
         (
            'bad maxdives',
            {
               'bad' => $arg,
               'dir'       => $dir,
               'bitmask'   => $bitmask,
            }
         ) if $arg !~ /\D/o;

      $MAXDIVES = $arg;
   }

   $MAXDIVES
}


# --------------------------------------------------------
# File::Util::readlimt()
# --------------------------------------------------------
sub readlimit {

   my($arg) = myargs(@_);

   if (defined($arg)) {
      return $this->_throw
         (
            'bad readlimit',
            {
               'bad' => $arg,
            }
         ) if $arg !~ /\D/o;

      $READLIMIT = $arg;
   }

   $READLIMIT
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
   my($filename)  = $in->{'file'}      || $in->{'filename'} || '';
   my($mode)      = $in->{'mode'}      || 'write';
   my($bitmask)   = $in->{'bitmask'}   || 0777;
   my($fh)        = undef;
   my($path)      = '';
   my(@dirs)      = ();

   $filename ||= $$in{'filename'}; $filename ||= ''; $path = $filename;

   # if the call to this method didn't include a filename to which the caller
   # wants us to write, then complain about it
   return $this->_throw
      (
         'no input',
         {
            'meth'      => 'write_file',
            'missing'   => 'a file name to create, write, or append',
            'opts'      => $opts,
         }
      )
   unless length($filename);

   # if prospective filename contains 2+ dir separators in sequence then
   # this is a syntax error we need to whine about
   return $this->_throw
      (
         'bad chars',
         {
            'string'    => $filename,
            'purpose'   => 'the name of a file or directory',
            'opts'      => $opts,
         }
      )
   if ($filename =~ /(?:$DIRSPLIT){2,}/);

   # remove trailing directory seperator
   $filename =~ s/$DIRSPLIT$//;

   # determine existance of the file path, make directory(ies) for the
   # path if the full directory path doesn't exist
   @dirs = split(/$DIRSPLIT/, $filename);

   # if prospective file name has illegal chars then complain
   foreach (@dirs) {

      return $this->_throw
         (
            'bad chars',
            {
               'string'    => $_,
               'purpose'   => 'the name of a file or directory',
               'opts'      => $opts,
            }
         )
      if (!$this->valid_filename($_));
   }

   if (scalar(@dirs) > 0) {

      $filename = pop(@dirs); $path = join(SL, @dirs);
   }

   if (length($path) > 0) {

      $path = '.' . SL . $path if ($path !~ /(?:^\/)|(?:^\w\:)/o);
   }
   else { $path = '.'; }

   if (!(-e $path)) { $this->make_dir($path, $bitmask); }

   my($openarg) = qq[$path$SL$filename];


   if ($mode eq 'write' or $mode eq 'append') {

      # Check whether or not we have permission to open and perform writes
      # on this file.

      if (-e $openarg) {

         return $this->_throw
            (
               'cant fwrite',
               {
                  'filename'  => $openarg,
                  'dirname'   => $path . SL,
                  'opts'      => $opts,
               }
            )
         unless (-w $openarg);
      }
      else {

         # If file doesn't exist and the path isn't writable, the error is
         # one of unallowed creation.
         return $this->_throw
            (
               'cant fcreate',
               {
                  'filename'  => $openarg,
                  'dirname'   => $path . SL,
                  'opts'      => $opts,
               }
            )
         unless (-w $path . SL);
      }
   }
   elsif ($mode eq 'read') {

      # Check whether or not we have permission to open and perform reads
      # on this file, starting with file's housing directory.

      return $this->_throw
         (
            'cant dread',
            {
               'filename'  => $path . SL . $filename,
               'dirname'   => $path . SL,
               'opts'      => $opts,
            }
         )
      unless (-r $path . SL);

      # Check the readability of the file itself
      return $this->_throw
         (
            'cant fread',
            {
               'filename'  => $path . SL . $filename,
               'dirname'   => $path . SL,
               'opts'      => $opts,
            }
         )
      unless (-r $path . SL . $filename);
   }
   else {

      return $this->_throw
         (
            'no input',
            {
               'meth'      => 'open_handle',
               'missing'   => q[a valid IO mode. (eg- 'read', 'write'...],
               'opts'      => $opts,
            }
         )
   }

   # we need a unique filehandle
   do { $fh = int(rand(time)) . $$; $fh = eval('*' . 'OPEN_TO_FH' . $fh) }
   while ( fileno($fh) );

   # if you use the '--no-lock' option you are probably inefficient
   if ($$opts{'--no-lock'} || !$USE_FLOCK) {

      # get open mode
      $mode = $$MODES{'popen'}{ $mode };

      open($fh, $mode . $openarg) or
         return $this->_throw
            (
               'bad open',
               {
                  'filename'  => $openarg,
                  'mode'      => $mode,
                  'exception' => $!,
                  'cmd'       => $mode . $openarg,
                  'opts'      => $opts,
               }
            );
   }
   else {

      # open read-only first to safely check if we can get a lock.
      if (-e $openarg) {

         open($fh, '<' . $openarg) or
            return $this->_throw
               (
                  'bad open',
                  {
                     'filename'  => $openarg,
                     'mode'      => 'read',
                     'exception' => $!,
                     'cmd'       => $mode . $openarg,
                     'opts'      => $opts,
                  }
               );

         # lock file before I/O on platforms that support it
         my($lockstat) = $this->_seize($openarg, $fh);

         return($lockstat) unless $lockstat;

         if ($mode ne 'read') {

            open($fh, $$MODES{'popen'}{ $mode } . $openarg) or
               return $this->_throw
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
                  );
         }
      }
      else {

         open($fh, $$MODES{'popen'}{ $mode } . $openarg) or
            return $this->_throw
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
# File::Util::return_path()
# --------------------------------------------------------
sub return_path { my($f) = myargs(@_); $f =~ s/(^.*)$DIRSPLIT.*/$1/o; $f }


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

   $in = shift(@_)||{}; $in->{'_pak'} = __PACKAGE__;

   map { $_ = defined($_) ? $_ : 'undefined value' } keys(%$in);

   PLAIN_ERRORS:

   my($bad_news) =
      CORE::eval
         (
            q{<<__ERRORBLOCK__}
            . &NL . &_errors($error)
            . &NL . q{__ERRORBLOCK__}
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
$in->{'_pak'} can't open
   $EBL$in->{'filename'}$EBR
because no such file or directory exists.

Origin:     This is *most likely* due to human error.
Solution:   Cannot diagnose.  A human must investigate the problem.
__bad_open__


# BAD FLOCK RULE POLICY
'bad flock rules' => <<'__bad_lockrules__',
Invalid file locking policy can not be implemented.  $in->{'_pak'}::flock_rules
does not accept one or more of the policy keywords passed to this method.

   Invalid Policy specified: $EBL@{[
   join ' ', map { '[undef]' unless defined $_ } @{ $in->{'all'} } ]}$EBR

   flock_rules policy in effect before invalid policy failed:
      $EBL@ONLOCKFAIL$EBR

   Proper flock_rules policy includes one or more of the following recognized
   keywords specified in order of precedence:
      BLOCK         waits to try getting an exclusive lock
      FAIL          dies with stack trace
      WARN          warn()s about the error with a stack trace
      IGNORE        ignores the failure to get an exclusive lock
      UNDEF         returns undef
      ZERO          returns 0

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__bad_lockrules__


# CAN'T READ FILE
'cant fread' => <<'__cant_read__',
Permissions conflict.  $in->{'_pak'} can't read the contents of this file:
   $EBL$in->{'filename'}$EBR

   Due to insufficient permissions, the system has denied Perl the right to
   view the contents of this file.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777 ]}$EBR

   The directory housing it has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with $in->{'_pak'}.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks $in->{'_pak'} to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_read__


# CAN'T CREATE FILE
'cant fcreate' => <<'__cant_write__',
Permissions conflict.  $in->{'_pak'} can't create this file:
   $EBL$in->{'filename'}$EBR

   $in->{'_pak'} can't create this file because the system has denied Perl
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
            can occur however, but this doesn't have to do with $in->{'_pak'}.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks $in->{'_pak'} to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T WRITE TO FILE
'cant fwrite' => <<'__cant_write__',
Permissions conflict.  $in->{'_pak'} can't write to this file:
   $EBL$in->{'filename'}$EBR

   Due to insufficient permissions, the system has denied Perl the right
   to modify the contents of this file.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777) ]}$EBR

   Parent directory has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with $in->{'_pak'}.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks $in->{'_pak'} to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T LIST DIRECTORY
'cant dread' => <<'__cant_read__',
Permissions conflict.  $in->{'_pak'} can't list the contents of this directory:
   $EBL$in->{'dirname'}$EBR

   Due to insufficient permissions, the system has denied Perl the right to
   view the contents of this directory.  It has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'filename'}))[2] & 0777) ]}$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with $in->{'_pak'}.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks $in->{'_pak'} to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_read__


# CAN'T CREATE DIRECTORY
'cant dcreate' => <<'__cant_write__',
Permissions conflict.  $in->{'_pak'} can't create:
   $EBL$in->{'filename'}$EBR

   $in->{'_pak'} can't create this directory because the system has denied
   Perl the right to create files in the parent directory.

   Parent directory: (path may be relative and/or redundant)
      $EBL$in->{'dirname'}$EBR

   Parent directory has a bitmask of: (octal number)
      $EBL@{[ sprintf('%04o',(stat($in->{'dirname'}))[2] & 0777) ]}$EBR

Origin:     This is *most likely* due to human error.  External system errors
            can occur however, but this doesn't have to do with $in->{'_pak'}.
Solution:   A human must fix the conflict by adjusting the file permissions
            of directories where a program asks $in->{'_pak'} to perform I/O.
            Try using Perl's chmod command, or the native system chmod()
            command from a shell.
__cant_write__


# CAN'T OPEN
'bad open' => <<'__bad_open__',
$in->{'_pak'} can't open this file for $EBL$in->{'mode'}$EBR:
   $EBL$in->{'filename'}$EBR

   The system returned this error:
      $EBL$in->{'exception'}$EBR

   $in->{'_pak'} used this directive in its attempt to open the file
      $EBL$in->{'cmd'}$EBR

   Current flock_rules policy:
      $EBL@ONLOCKFAIL$EBR

Origin:     This is *most likely* due to human error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_open__


# BAD CLOSE
'bad close' => <<'__bad_close__',
$in->{'_pak'} couldn't close this file after $EBL$in->{'mode'}$EBR
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
$in->{'_pak'} couldn't truncate() on $EBL$in->{'filename'}$EBR after having
successfully opened the file in write mode.

The system returned this error:
   $EBL$in->{'exception'}$EBR

Current flock_rules policy:
   $EBL@ONLOCKFAIL$EBR

This is most likely _not_ a human error, but has to do with your system's
support for the C truncate() function.
__bad_systrunc__


# CAN'T GET FLOCK AFTER BLOCKING
'bad flock' => <<'__bad_lock__',
$in->{'_pak'} can't get a lock on the file
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
$in->{'_pak'} can't call open() on this file because it is a directory
   $EBL$in->{'filename'}$EBR

Origin:     This is a human error.
Solution:   Use $in->{'_pak'}::load_file() to load the contents of a file
            Use $in->{'_pak'}::list_dir() to list the contents of a directory
__bad_open__


# CAN'T OPENDIR ON A FILE
'called opendir on a file' => <<'__bad_open__',
$in->{'_pak'} can't opendir() on this file because it is not a directory.
   $EBL$in->{'filename'}$EBR

Use $in->{'_pak'}::load_file() to load the contents of a file
Use $in->{'_pak'}::list_dir() to list the contents of a directory

Origin:     This is a human error.
Solution:   Use $in->{'_pak'}::load_file() to load the contents of a file
            Use $in->{'_pak'}::list_dir() to list the contents of a directory
__bad_open__


# CAN'T MKDIR ON A FILE
'called mkdir on a file' => <<'__bad_open__',
$in->{'_pak'} can't auto-create a directory for this path name because it
already exists as a file.
   $EBL$in->{'filename'}$EBR

Origin:     This is a human error.
Solution:   Resolve naming issue between the existant file and the directory
            you wish to create.
__bad_open__


# EXCEEDED READLIMIT
'readlimit exceeded' => <<'__readlimit__',
$in->{'_pak'} can't load file: $EBL$in->{'filename'}$EBR
into memory because its size exceeds the maximum file size allowed
for a read.

The size of this file is $EBL$in->{'size'}$EBR bytes.

Currently the read limit is set at $EBL$READLIMIT$EBR bytes.

Origin:     This is a human error.
Solution:   Consider setting the limit to a higher number of bytes.
__readlimit__


# BAD CALL TO File::Util::max_dives
'bad maxdives' => <<'__maxdives__',
Bad call to $in->{'_pak'}::max_dives().  This method can only be called with
a numeric value (bytes).  Non-integer numbers will be converted to integer 
format if specified (numbers like 5.2), but don't do that, it's inefficient.

This operation aborted.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__maxdives__


# EXCEEDED MAXDIVES
'maxdives exceeded' => <<'__maxdives__',
Recursion limit reached at $EBL${\ $in->{'maxdives'} || $MAXDIVES }$EBR dives.
Maximum number of subdirectory dives is set to the value returned by
$in->{'_pak'}::max_dives().  Try manually setting the value to a higher number
before calling list_dir() with option --follow or --recurse (synonymous).  Do
so by calling $in->{'_pak'}::max_dives() with the numeric argument corresponding
to the maximum number of subdirectory dives you want to allow when traversing
directories recursively.

This operation aborted.

Origin:     This is a human error.
Solution:   Consider setting the limit to a higher number.
__maxdives__


# BAD CALL TO File::Util::readlimit
'bad maxdives' => <<'__maxdives__',
Bad call to $in->{'_pak'}::readlimit().  This method can only be called with
a numeric value (bytes).  Non-integer numbers will be converted to integer 
format if specified (numbers like 5.2), but don't do that, it's inefficient.

This operation aborted.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__maxdives__


# BAD OPENDIR
'bad opendir' => <<'__bad_opendir__',
$in->{'_pak'} can't opendir this on $EBL$dir$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Origin:     Could be either human _or_ system error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_opendir__


# BAD MAKEDIR
'bad make_dir' => <<'__bad_make_dir__',
$in->{'_pak'} had a problem with the system while attempting to create the
directory you specified with a bitmask of $EBL$in->{'bitmask'}$EBR

directory: $EBL$in->{'dir'}$EBR

The system returned this error:
   $EBL$in->{'exception'}$EBR

Origin:     Could be either human _or_ system error.
Solution:   Cannot diagnose.  A Human must investigate the problem.
__bad_make_dir__


# BAD CALL TO METHOD FOO
'no input' => <<'__no_input__',
$in->{'_pak'} can't honor your call to $EBL$in->{'_pak'}::$in->{'meth'}()$EBR
because you didn't provide $EBL@{[$in->{'missing'}||'the required input']}$EBR

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__no_input__


# PLAIN ERROR TYPE
'plain error' => <<'__plain_error__',
$in->{'_pak'} failed with the following message:
$_[0]
__plain_error__


# INVALID ERROR TYPE
'unknown error message' => <<'__foobar_input__',
$in->{'_pak'} failed with an invalid error-type designation.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__foobar_input__


# EMPTY ERROR TYPE
'empty error' => <<'__no_input__',
$in->{'_pak'} failed with an empty error-type designation.

Origin:     This is a human error.
Solution:   A human must fix the programming flaw.
__no_input__


# BAD CHARS
'bad chars' => <<'__bad_chars__',
$in->{'_pak'} can't use this string for $EBL$in->{'purpose'}$EBR.
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
$in->{'_pak'} can't unlock file with an invalid file handle reference:
   $EBL$fh$EBR is not a valid filehandle

Origin:     This is most likely an internal error in the $in->{'_pak'} module.
Solution:   A human must investigate the problem.  Send a usenet post with this
            error message in its entirety to usenet group:
            $EBL news:comp.lang.perl.modules $EBR
__bad_handle__

 'foo' => '' }->{ shift(@_) || 'unknown error message' }
}
