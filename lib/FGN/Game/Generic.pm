use rjbs;
package FGN::Game::Generic;

use JSON;
use Plack::Request;
use Router::Simple;

my $JSON = JSON->new->utf8->canonical;

sub _build_router ($self) {
  my $router = Router::Simple->new;

  my $P = { method => 'POST' };

  $router->connect("/create-game", { action => 'create_game' }, $P);
  $router->connect("/join-game",   { action => 'join_game'   }, $P);
  $router->connect("/move",        { action => 'play'        }, $P);
  $router->connect("/render",      { action => 'render'      }, $P);

  $self->{router} = $router;
  return;
}

sub new ($class, $arg = {}) {
  my $self = bless {}, $class;
  $self->_build_router;

  return $self;
}

sub app ($self) {
  return sub ($env) {
    my $match = $self->{router}->match($env);

    unless ($match) {
      return [
        404,
        [ 'Content-Type' => 'application/json' ],
        [ '{"error":"no such resource"}' ],
      ];
    }

    my $req = Plack::Request->new($env);
    my $body = do { local $/; my $handle = $req->body; <$handle> };
    my $data = $body ? eval { $JSON->decode($body) } : {};

    my $method = $match->{action};

    my $return = $self->$method($data);

    return [
      ($return->{result}{error} ? 400 : 200),
      [ "Content-Type", "application/json" ],
      [ $JSON->encode($return) ],
    ];
  }
}

1;
