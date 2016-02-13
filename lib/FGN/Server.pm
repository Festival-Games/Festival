use rjbs;
package FGN::Server;

use JSON ();
use Plack::Request;
use Path::Tiny;

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
use LWP::UserAgent;

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
    ua => LWP::UserAgent->new,

    games    => {},
    openings => {},
    game_url => $arg->{game_url} // {}, # having no game servers is silly

    storage_filename => "fgn.json",
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

sub _get_storage ($self) {
  my $file = $self->{storage_filename};
  my $content = -e $file ? `cat $file` : "{}";

  $JSON->decode($content);
}

sub _save_storage ($self, $storage) {
  my $file = $self->{storage_filename};
  my $json = $JSON->encode($storage);
  path($file)->spew($json);
  return;
}

sub _game_request ($self, $game, $method, $path, $arg) {
  my $ua     = $self->{ua};
  my $server = $self->{game_url}{$game};
     $server =~ s{/\z}{};
  my $url    = "$server/$path";

  my $res;
  if ($method eq 'GET') {
    warn "args provided on GET request for $url";
    $res = $ua->get($path);
  } else {
    my $method = lc $method;
    my $json   = $JSON->encode($arg);
    $res = $ua->$method($url,
      'Content-Type' => 'application/json',
      Content => $json,
    );
  }

  die "didn't get back JSON"
    unless my $data = eval { $JSON->decode( $res->decoded_content ); };

  return $data;
}

sub join_game ($self, $req, $match) {
  return mkerr(403 => "you must authenticate") unless $match->{user};

  my $gametype = $match->{gametype};
  return mkerr(404 => "no such game type") unless $self->{game_url}{$gametype};

  my $storage = $self->_get_storage;

  my $openings = $storage->{openings}{$gametype};

  my $uid = $match->{user}->username;

  my $joinable;
  for my $id (keys %$openings) {
    next if grep { defined && $_ eq $uid } values $openings->{$id}->%*;
    $joinable = $id;
    last;
  }

  unless ($joinable) {
    my $res = $self->_game_request($gametype => POST => 'create-game' => {
      player_id => $uid,
      format    => $req->parameters->{format} // 'json',
    });

    return $self->process_res($gametype, undef, $req, $res);
  }

  my $res = $self->_game_request($gametype => POST => 'join-game' => {
    game      => $storage->{games}{ $gametype }{$joinable},
    game_id   => $joinable,
    player_id => $uid,
    format    => $req->parameters->{format} // 'json',
  });

  return $self->process_res($gametype, $joinable, $req, $res);
}

sub process_res ($self, $gametype, $id, $req, $res) {
  my ($result, $update) = $res->@{ qw(result update) };
  return mkerr(403 => $result->{error}) if $result->{error};

  my $storage = $self->_get_storage;

  my $game_storage = $storage->{games}{$gametype} //= {};
  my $openings     = $storage->{openings}{$gametype} //= {};

  state $next = 1;

  unless (defined $id) {
    $id = $next++
  }

  if (defined $update->{openings}) {
    $openings->{$id} = $update->{openings};
  } elsif (exists $update->{openings}) {
    delete $openings->{$id};
  }

  if (defined $update->{game}) {
    $game_storage->{$id} = $update->{game};
  } elsif (exists $update->{game}) {
    delete $game_storage->{$id};
    delete $openings->{$id};
  }

  $self->_save_storage($storage);

  my $give_loc = $req->method eq 'POST' || $req->method eq 'PUT';

  return [
    200, # TODO: needs to be determined by response
    [
      "Content-Type" => $result->{content_type},
      ($give_loc ? (Location => "/game/$gametype/$id") : ()),
    ],
    [ $result->{content} ],
  ];
}

sub game ($self, $req, $match) {
  my $gametype = $match->{gametype};
  return mkerr(404 => "no such game type") unless $self->{game_url}{$gametype};

  my $storage = $self->_get_storage;
  my $game = $storage->{games}{$gametype}{ $match->{game_id} };

  return mkerr(404 => "no such game") unless $game;

  my $status = 200;

  if ($req->method eq 'PUT') {
    my $move = $self->body_data($req);

    return mkerr(403 => "bogus move") unless $move;

    my $res = $self->_game_request($gametype, POST => move => {
      game      => $game,
      player_id => $match->{user}->username,
      move      => $move,
      format    => $req->parameters->{format} // 'json',
    });

    return $self->process_res($gametype, $match->{game_id}, $req, $res);
  }

  if ($req->method eq 'GET') {
    my $res = $self->_game_request($gametype, POST => render => {
      game      => $game,
      player_id => $match->{user}->username,
      format    => $req->parameters->{format} // 'json',
    });

    return $self->process_res($gametype, $match->{game_id}, $req, $res);
  }

  return [
    405,
    [ "Content-Type", "application/json" ],
    [ '{"error":"only GET or POST allowed"}' ],
  ];
}

1;
