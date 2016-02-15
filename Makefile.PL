use 5.008001;
use ExtUtils::MakeMaker 6.48;

# On Ubuntu/Debian, you'll need at minimum:
#  * libssl-dev
#  * libreadline-dev
#  * libdb-dev

WriteMakefile(
  "ABSTRACT"          => "Festival Games Server",
  "AUTHOR"            => "Ricardo SIGNES <rjbs\@cpan.org>",
  "BUILD_REQUIRES"    => { },
  "LICENSE" => "perl",
  "NAME"              => "Festival",
  "PREREQ_PM"         => {
    "JSON"           => 0,
    "JSON::PP"       => 0,
    "List::Util"     => 0,
    "lib"            => 0,
    "LWP::UserAgent" => 0,
    "MIME::Base64"   => 0,
    "parent"         => 0,
    "Path::Tiny"     => 0,
    "Plack"          => 0,
    "rjbs"           => 0,
    "Router::Simple" => 0,
    "warnings"       => 0,
  },
  "MIN_PERL_VERSION"  => '5.020000',
  "VERSION_FROM"      => "lib/Festival.pm",
);
