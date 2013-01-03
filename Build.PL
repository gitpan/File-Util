
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "File::Temp" => 0,
    "Module::Build" => "0.3601",
    "Test" => 0
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
  "dist_version" => "3.36",
  "license" => "perl",
  "module_name" => "File::Util",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "AutoLoader" => 0,
    "Config" => 0,
    "Exception::Handler" => "1.00_0",
    "Exporter" => 0,
    "ExtUtils::MakeMaker" => 0,
    "Fcntl" => 0,
    "File::Temp" => 0,
    "Module::Build" => 0,
    "Test" => 0,
    "constant" => 0,
    "perl" => "5.006",
    "strict" => 0,
    "vars" => 0,
    "warnings" => 0
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
