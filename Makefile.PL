use ExtUtils::MakeMaker;
require 5.6.0;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile
   (
   'ABSTRACT'     => 'Safe, Easy File Handling',
   'AUTHOR'       => 'Tommy Butler <perlmod@atrixnet.com>',
   'INSTALLDIRS'  => 'perl',
   'NAME'         => 'File::Util',
   'VERSION_FROM' => 'Util.pm',
   'PREREQ_PM'    =>
      {
         'OOorNO' => 0.00_2,
         'Handy::Dandy'  => 1.30_4,
         'Exception::Handler' => 1.00_0,
         'Handy::Dandy::TimeTools' => 0.01_5,
      },
   'linkext'      => { LINKTYPE => '' }, # no link needed
   'dist'         =>
      {
         'COMPRESS'  => 'gzip -9f',
         'SUFFIX'    => 'gz',
         'ZIP'       => '/usr/bin/zip',
         'ZIPFLAGS'  => '-rl',
      }
   );

__END__
   * NAME
   * SYNOPSIS
   * DESCRIPTION
   * INSTALLATION
   * EXPORT
   * EXPORT_OK
   * GLOBAL VARIABLES
   * PUBLIC METHODS
   * PRIVATE METHODS
   * EXAMPLES
   * BUGS
   * AUTHOR
   * COPYRIGHT
   * SEE ALSO
