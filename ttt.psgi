#!perl
use rjbs;

use lib 'lib';
use FGN::Server;
use FGN::Game::TTT;

my $server = FGN::Server->new({
  game_handler => { 'ttt' => 'FGN::Game::TTT' },
});

$server->app;
