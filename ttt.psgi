#!perl
use rjbs;

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

package TTT::Game {
  sub create_game ($class, $arg) {
    my $game = {
      next  => 'x',
      board => [ (undef) x 9 ],
      players => { o => undef, x => undef },
    };

    my @options = qw(x o);
    $game->{players}{ $options[ rand @options ] } = $arg->{player_id};

    return {
      game     => $game,
      openings => { $game->{players}->%* },
    };
  }

  sub join_game ($class, $arg) {
    my $game = $arg->{game};

    my @options = grep {; ! defined $game->{players}{$_} }
                  keys $game->{players}->%*;

    return { error => "game is full" } unless @options;

    $game->{players}{ $options[ rand @options ] } = $arg->{player_id};

    return {
      game     => $game, # make dumb hash
      openings => @options > 1 ? { $game->{players}->%* } : undef,
    };
  }

  sub play ($self, $arg) {
    my $player = $arg->{player};
    my $game   = $arg->{game};
    my $move   = $arg->{move};
    my $where  = $move->{where};

    return { error => "game is ended" } if $game->{over};

    return { error => "game not yet begun" }
      if grep {; ! defined } values $game->{players}->%*;

    return { error => "not your turn" }
      unless $game->{players}{ $game->{next} } eq $player;

    return { error => "bogus play" } unless defined $where && $where =~ /\A[0-8]\z/;

    return { error => "space already claimed" } if defined $game->{board}[$where];

    $game->{board}[$where] = $game->{next};
    $game->{next} = $game->{next} eq 'x' ? 'o' : 'x';

    if (my $winner = $self->winner($game)) {
      $game->{winner} = $winner;
      $game->{over} = 1; # XXX true
    } elsif (9 == grep {; defined } $game->{board}->@*) {
      $game->{over} = 1; # XXX true
    }

    return {
      game => $game,
    };
  }

  sub winner ($self, $game) {
    my @board = $game->{board}->@*;
    return $board[0]
      if ($board[0] eq $board[1] && $board[0] eq $board[2])
      || ($board[0] eq $board[4] && $board[0] eq $board[8])
      || ($board[0] eq $board[3] && $board[0] eq $board[6]);

    return $board[1]
      if ($board[1] eq $board[4] && $board[1] eq $board[7]);

    return $board[2]
      if ($board[2] eq $board[4] && $board[2] eq $board[6])
      || ($board[2] eq $board[5] && $board[2] eq $board[8]);

    return $board[3]
      if ($board[3] eq $board[4] && $board[3] eq $board[5]);

    return $board[6]
      if ($board[6] eq $board[7] && $board[6] eq $board[8]);

    return;
  }

  sub as_json ($self, $game) {
    $JSON->encode($game);
  }

  sub as_text ($self, $game) {
    my $str = q{};

    my $board = $game->{board};
    for my $i (0 .. 2) {
      for my $j (0 .. 2) {
        my $c = $i * 3 + $j;
        $str .= $board->[$c] // '.';
        $str .= "\n" if $j == 2;
      }
    }

    for my $pos (sort keys $game->{players}->%*) {
      $str .= "$pos: $game->{players}{ $pos }\n";
    }

    if (my $winner = $game->{winner}) {
      $str .= qq{\nThe winner is: $winner\n"};
    } elsif ($game->{over}) {
      $str .= qq{\nThe game has ended in a draw.\n"};
    } elsif (my $next = $game->{next}) {
      $str .= qq{\nNext to play is: $next\n};
    } else {
      $str .= qq{\nWaiting on players...\n};
    }

    return $str;
  }
}

package TTT::Web {
  use MIME::Base64;
  use Router::Simple;
  use List::Util ();

  my $router = Router::Simple->new;
  $router->connect("/dump", { action => 'dumpall' }, { method => 'GET' })
         ->connect("/game/{game:[1-9][0-9]*}",
                    { action => 'game' }, { method => [ qw( GET PUT ) ] })
         ->connect("/games", { action => 'join_game' }, { method => 'PUT' })
         ->connect("/player/{username:[A-Za-z][0-9A-Za-z]{3,31}}",
                    { action => 'player' }, { method => 'GET' })
         ->connect("/player/{username:[A-Za-z][0-9A-Za-z]{3,31}}",
                    { action => 'new_player' }, { method => 'PUT' });

  sub mkerr ($err, $desc) {
    return [
      $err,
      [ "Content-Type", "application/json" ],
      [ $JSON->encode({ error => $desc }) ],
    ];
  }

  sub new ($class) {
    my $guts = {
      games    => {},
      openings => {},
    };

    return bless $guts => $class;
  }

  sub dumpall ($self, $req, $match) {
    return [
      200,
      [ 'Content-type', 'application/json' ],
      [ $JSON->encode({ player => Game::Player->dump_all, %$self }) ],
    ];
  }

  sub auth ($self, $req) {
    return unless my $header = $req->header('Authorization');
    my ($username, $password) = split /:/, decode_base64($header), 2;
    return Game::Player->login($username, $password);
  }

  sub app ($self) {
    return sub ($env) {
      my $match = $router->match($env);

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

    my $openings = $self->{openings};

    my $uid = $match->{user}->username;

    my $joinable;
    for my $id (keys %$openings) {
      next if grep { $_ eq $uid } values $openings->{$id}->%*;
      $joinable = $id;
      last;
    }

    unless ($joinable) {
      my $res = TTT::Game->create_game({
        player_id => $uid,
      });

      return $self->process_res(undef, $res);
    }

    my $res = TTT::Game->join_game({
      game      => $self->{games}{$joinable},
      game_id   => $joinable,
      player_id => $uid,
    });

    return $self->process_res($joinable, $res);
  }

  sub process_res ($self, $id, $res) {
    return mkerr(403 => $res->{error}) if $res->{error}; # XXX this is crap

    state $next = 1;
    $id = $next++ unless defined $id;

    if (defined $res->{openings}) {
      $self->{openings}{$id} = $res->{openings};
    } elsif (exists $res->{openings}) {
      delete $self->{openings}{$id};
    }

    if (defined $res->{game}) {
      $self->{games}{$id} = $res->{game};
    } elsif (exists $res->{game}) {
      delete $self->{games}{$id};
      delete $self->{openings}{$id};
    }

    my $json = $self->{games}{$id}
             ? TTT::Game->as_json($self->{games}{$id})
             : '{"ok":true}';

    return [
      200, # TODO: needs to be determined by response
      [ "Content-Type" => "application/json" ],
      [ $json ],
    ];
  }

  sub game ($self, $req, $match) {
    my $game = $self->{games}{ $match->{game} };

    return mkerr(404 => "no such game") unless $game;

    my $status = 200;

    if ($req->method eq 'PUT') {
      my $move = $self->body_data($req);

      return mkerr(403 => "bogus move") unless $move;

      my $res = TTT::Game->play({
        game   => $game,
        player => $match->{user}->username,
        move   => $move,
      });

      return $self->process_res($match->{game}, $res);
    }

    return $self->_game_res($status, [], $req, $game);
  }

  sub _game_res ($self, $status, $hdr, $req, $game) {
    my $format = $req->parameters->{format} // 'json';

    if ($format eq 'text') {
      return [
        $status,
        [ @$hdr, "Content-Type", "text/plain", ],
        [ TTT::Game->as_text($game) ],
      ];
    } else {
      return [
        $status,
        [ @$hdr, "Content-Type", "application/json", ],
        [ TTT::Game->as_json($game) ],
      ];
    }
  }
}

TTT::Web->new->app
