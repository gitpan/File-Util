
use strict;
use warnings;

use 5.006;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Easy, versatile, portable file handling",
  "AUTHOR" => "Tommy Butler",
  "BUILD_REQUIRES" => {
    "AutoLoader" => 0,
    "Config" => 0,
    "Cwd" => 0,
    "Exception::Handler" => "1.00_0",
    "Exporter" => 0,
    "ExtUtils::MakeMaker" => 0,
    "Fcntl" => 0,
    "File::Find" => 0,
    "File::Temp" => 0,
    "Module::Build" => "0.3601",
    "Scalar::Util" => 0,
    "Test" => 0,
    "Test::Fatal" => 0,
    "Test::More" => "0.88",
    "Test::NoWarnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30",
    "Module::Build" => "0.3601"
  },
  "DISTNAME" => "File-Util",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "File::Util",
  "PREREQ_PM" => {
    "Config" => 0,
    "Data::Dumper" => 0,
    "Exception::Handler" => 0,
    "Exporter" => 0,
    "Fcntl" => 0,
    "Scalar::Util" => 0,
    "Time::HiRes" => 0,
    "constant" => 0,
    "strict" => 0,
    "subs" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "VERSION" => "4.130483",
  "test" => {
    "TESTS" => "t/*.t t/extended/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



