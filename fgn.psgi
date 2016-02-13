#!perl
use rjbs;

use lib 'lib';
use FGN::Server;
use FGN::Game::Oware;
use FGN::Game::TTT;

my $server = FGN::Server->new({
  game_url => {
    oware => 'http://localhost:5002',
    ttt   => 'http://localhost:5001',
  },
});

$server->app;
