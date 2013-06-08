
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "ExtUtils::MakeMaker" => "6.30",
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Easy, versatile, portable file handling",
  "dist_author" => [
    "Tommy Butler"
  ],
  "dist_name" => "File-Util",
  "dist_version" => "4.131591",
  "license" => "perl",
  "module_name" => "File::Util",
  "recommends" => {
    "Unicode::UTF8" => "0.58"
  },
  "recursive_test_files" => 1,
  "requires" => {
    "Config" => 0,
    "Exporter" => 0,
    "Fcntl" => 0,
    "Scalar::Util" => 0,
    "constant" => 0,
    "perl" => "5.008001",
    "strict" => 0,
    "subs" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "script_files" => [],
  "test_requires" => {
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
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
