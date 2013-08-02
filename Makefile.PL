
use strict;
use warnings;

use 5.008001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Easy, versatile, portable file handling",
  "AUTHOR" => "Tommy Butler",
  "BUILD_REQUIRES" => {
    "Module::Build" => "0.3601"
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
    "Exporter" => 0,
    "Fcntl" => 0,
    "Scalar::Util" => 0,
    "constant" => 0,
    "strict" => 0,
    "subs" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "TEST_REQUIRES" => {
    "AutoLoader" => 0,
    "Config" => 0,
    "Cwd" => 0,
    "Exporter" => 0,
    "ExtUtils::MakeMaker" => 0,
    "Fcntl" => 0,
    "File::Find" => 0,
    "File::Temp" => 0,
    "Module::Build" => 0,
    "Scalar::Util" => 0,
    "Test" => 0,
    "Test::More" => "0.88",
    "Test::NoWarnings" => 0,
    "utf8" => 0
  },
  "VERSION" => "4.132140",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

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



