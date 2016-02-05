use rjbs;
package FGN::Server;

use JSON ();
use Plack::Request;

my $JSON = JSON->new->utf8->canonical;

package Game::Player {
  my %PLAYER;

  sub new ($class, $username, $password) {
    return if $PLAYER{ fc $username };
    return unless length $password and $username =~ /\A [a-z][a-z0-9]+ \z/ix;

    my $self = bless { username => $username, password => $password };
    $PLAYER{ fc $username } = $self;
    return $self;
  }

  sub dump_all ($self) {
    return { map {; $_ => { $PLAYER{$_}->%* } } keys %PLAYER };
  }

  sub username ($self) { $self->{username} }


  sub player_named ($self, $name) { $PLAYER{ fc $name } }

  sub login ($class, $username, $password) {
    return unless my $self = $PLAYER{ fc $username };
    return unless $self->{password} eq $password;
    return $self;
  }
}

use MIME::Base64;
use Router::Simple;
use List::Util ();

sub _build_router {
  my ($self) = @_;

  my $router = Router::Simple->new;
  $router->connect("/dump", { action => 'dump_all' }, { method => 'GET' });

  $router->connect(
    "/game/{gametype:[-a-z0-9]+}/{game_id:[1-9][0-9]*}",
    { action => 'game' },
    { method => [ qw( GET PUT ) ] }
  );

  $router->connect(
    "/game/{gametype:[-a-z0-9]+}/games",
    { action => 'join_game' },
    { method => 'PUT' }
  );

  $router->connect("/player/{username:[A-Za-z][0-9A-Za-z]{3,31}}",
                   { action => 'player' }, { method => 'GET' })
         ->connect("/player/{username:[A-Za-z][0-9A-Za-z]{3,31}}",
                   { action => 'new_player' }, { method => 'PUT' });

  $self->{router} = $router;
  return;
}

sub mkerr ($err, $desc) {
  return [
    $err,
    [ "Content-Type", "application/json" ],
    [ $JSON->encode({ error => $desc }) ],
  ];
}

sub new ($class, $arg) {
  my $self = {
    games    => {},
    openings => {},
    game_handler => $arg->{game_handler} // {}, # having no handlers is silly
  };

  bless $self => $class;

  $self->_build_router;

  return $self;
}

sub router ($self) { $self->{router} }

sub dump_all ($self, $req, $match) {
  my $guts = {
    player => Game::Player->dump_all,
    %$self,
  };

  delete $guts->{router};

  return [
    200,
    [ 'Content-type', 'application/json' ],
    [ $JSON->encode($guts) ],
  ];
}

sub auth ($self, $req) {
  return unless my $header = $req->header('Authorization');
  my ($username, $password) = split /:/, decode_base64($header), 2;
  return Game::Player->login($username, $password);
}

sub app ($self) {
  return sub ($env) {
    my $match = $self->router->match($env);

    return mkerr(404 => "no such resource") unless $match;

    my $req = Plack::Request->new($env);
    $match->{user} = $self->auth($req);

    my $method = $match->{action};
    return $self->$method($req, $match);
  }
}

sub body_data ($self, $req) {
  my $body = do { local $/; my $handle = $req->body; <$handle> };
  my $data = $body ? eval { $JSON->decode($body) } : {};
  return $data;
}

sub player ($self, $req, $match) {
  my $player = Game::Player->player_named($match->{username});

  return mkerr(404 => "no such player") unless $player;

  return [
    200,
    [ 'Content-Type' => 'application/json' ],
    [ $JSON->encode({ username => $player->username }) ],
  ];
}

sub new_player ($self, $req, $match) {
  my $profile = $self->body_data($req);
  my $player  = Game::Player->new($match->{username}, $profile->{password});

  return mkerr(403 => "can't create user") unless $player;

  return [
    200,
    [ 'Content-Type' => 'application/json' ],
    [ $JSON->encode({ ok => 1 }) ],
  ];
}

sub join_game ($self, $req, $match) {
  return mkerr(403 => "you must authenticate") unless $match->{user};

  my $gametype = $match->{gametype};
  my $game_handler = $self->{game_handler}->{ $gametype };

  return mkerr(404 => "no such game type") unless $game_handler;

  my $openings = $self->{openings}{$gametype};

  my $uid = $match->{user}->username;

  my $joinable;
  for my $id (keys %$openings) {
    next if grep { defined && $_ eq $uid } values $openings->{$id}->%*;
    $joinable = $id;
    last;
  }

  unless ($joinable) {
    my $res = $game_handler->create_game({
      player_id => $uid,
    });

    return $self->process_res($gametype, undef, $res);
  }

  my $res = $game_handler->join_game({
    game      => $self->{games}{ $gametype }{$joinable},
    game_id   => $joinable,
    player_id => $uid,
  });

  return $self->process_res($gametype, $joinable, $res);
}

sub process_res ($self, $gametype, $id, $res) {
  return mkerr(403 => $res->{error}) if $res->{error}; # XXX this is crap

  my $game_handler = $self->{game_handler}{$gametype};
  my $game_storage = $self->{games}{$gametype} //= {};
  my $openings     = $self->{openings}{$gametype} //= {};

  state $next = 1;

  my $creating;
  unless (defined $id) {
    $creating = 1;
    $id = $next++
  }

  if (defined $res->{openings}) {
    $openings->{$id} = $res->{openings};
  } elsif (exists $res->{openings}) {
    delete $openings->{$id};
  }

  if (defined $res->{game}) {
    $game_storage->{$id} = $res->{game};
  } elsif (exists $res->{game}) {
    delete $game_storage->{$id};
    delete $openings->{$id};
  }

  my $json = $game_storage->{$id}
           ? $game_handler->as_json($game_storage->{$id})
           : '{"ok":true}';

  return [
    200, # TODO: needs to be determined by response
    [
      "Content-Type" => "application/json",
      ($creating ? (Location => "/game/$gametype/$id") : ()),
    ],
    [ $json ],
  ];
}

sub game ($self, $req, $match) {
  my $gametype = $match->{gametype};
  my $game_handler = $self->{game_handler}->{ $gametype };
  return mkerr(404 => "no such game type") unless $game_handler;

  my $game = $self->{games}{$gametype}{ $match->{game_id} };

  return mkerr(404 => "no such game") unless $game;

  my $status = 200;

  if ($req->method eq 'PUT') {
    my $move = $self->body_data($req);

    return mkerr(403 => "bogus move") unless $move;

    my $res = $game_handler->play({
      game   => $game,
      player => $match->{user}->username,
      move   => $move,
    });

    return $self->process_res($gametype, $match->{game_id}, $res);
  }

  return $self->_game_res($game_handler, $status, [], $req, $game);
}

sub _game_res ($self, $game_handler, $status, $hdr, $req, $game) {
  my $format = $req->parameters->{format} // 'json';

  if ($format eq 'text') {
    return [
      $status,
      [ @$hdr, "Content-Type", "text/plain", ],
      [ $game_handler->as_text($game) ],
    ];
  } else {
    return [
      $status,
      [ @$hdr, "Content-Type", "application/json", ],
      [ $game_handler->as_json($game) ],
    ];
  }
}

1;
