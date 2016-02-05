#!perl
use rjbs;

use lib 'lib';
use FGN::Server;
use FGN::Game::Oware;
use FGN::Game::TTT;

my $server = FGN::Server->new({
  game_handler => {
    oware => 'FGN::Game::Oware',
    ttt   => 'FGN::Game::TTT',
  },
});

$server->app;
