#!perl
use rjbs;

use JSON ();
use Plack::Request;

my $JSON = JSON->new->utf8->canonical;


package TTT::Player {
  my %PLAYER;

  sub new ($class, $username, $password) {
    return if $PLAYER{ fc $username };
    return unless length $password and $username =~ /\A [a-z][a-z0-9]+ \z/ix;

    my $self = bless { username => $username, password => $password };
    $PLAYER{ fc $username } = $self;
    return $self;
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
  sub new ($class) {
    bless {
      next  => 'x',
      board => [ 0 .. 8 ],
      players => { },
    } => $class;
  }

  sub next_player ($self) {
    return unless 2 == keys $self->{players}->%*;

    my ($next) = grep { $self->{players}{$_} eq $self->{next} }
                 keys $self->{players}->%*;

    return $next;
  }

  sub play ($self, $who, $where) {
    return -1 if $self->winner;
    return -1 unless $who and defined $where;
    return -1 unless $who->username eq $self->next_player;
    return -1 unless $where =~ /\A[0-8]\z/;
    return -1 unless $self->{board}[$where] eq $where;

    $self->{next} = $self->{next} eq 'x' ? 'o' : 'x';
    $self->{board}[$where] = $self->{players}{ $who->username };

    return 1 if $self->winner;

    return 0;
  }

  sub winner ($self) {
    return $self->{winner} if $self->{winner};
    my $winning_side = sub {
      my @board = $self->{board}->@*;
      return $board[0]
        if ($board[0] eq $board[1] && $board[0] eq $board[2])
        || ($board[0] eq $board[4] && $board[0] eq $board[8])
        || ($board[0] eq $board[3] && $board[0] eq $board[6]);

      return $board[1]
        if ($board[1] eq $board[4] && $board[0] eq $board[7]);

      return $board[2]
        if ($board[2] eq $board[4] && $board[0] eq $board[6])
        || ($board[2] eq $board[5] && $board[2] eq $board[8]);

      return $board[3]
        if ($board[3] eq $board[4] && $board[3] eq $board[5]);

      return $board[6]
        if ($board[6] eq $board[7] && $board[6] eq $board[8]);

      return
    }->();
  }

  sub as_json ($self) {
    $JSON->encode({ %$self });
  }

  sub as_text ($self) {
    my $str = q{};

    my $board = $self->{board};
    for my $i (0 .. 2) {
      for my $j (0 .. 2) {
        my $c = $i * 3 + $j;
        $str .= $board->[$c] eq $c ? '.' : $board->[$c];
        $str .= "\n" if $j == 2;
      }
    }

    for my $username (sort keys $self->{players}->%*) {
      $str .= "$self->{players}{$username}: $username\n";
    }

    if (my $winner = $self->winner) {
      $str .= qq{\nThe winner is: $winner\n"};
    } elsif (my $next = $self->next_player) {
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
  $router->connect("/game/{game:[1-9][0-9]*}",
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
    bless { games => {} } => $class;
  }

  sub auth ($self, $req) {
    return unless my $header = $req->header('Authorization');
    my ($username, $password) = split /:/, decode_base64($header), 2;
    return TTT::Player->login($username, $password);
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

  sub player ($self, $req, $match) {
    my $player = TTT::Player->player_named($match->{username});

    return mkerr(404 => "no such player") unless $player;

    return [
      200,
      [ 'Content-Type' => 'application/json' ],
      [ $JSON->encode({ username => $player->username }) ],
    ];
  }

  sub body_data ($self, $req) {
    my $body = do { local $/; my $handle = $req->body; <$handle> };
    my $data = $body ? eval { $JSON->decode($body) } : {};
    return $data;
  }

  sub new_player ($self, $req, $match) {
    my $profile = $self->body_data($req);
    my $player  = TTT::Player->new($match->{username}, $profile->{password});

    return mkerr(403 => "can't create user") unless $player;

    return [
      200,
      [ 'Content-Type' => 'application/json' ],
      [ $JSON->encode({ ok => 1 }) ],
    ];
  }

  sub join_game ($self, $req, $match) {
    return mkerr(403 => "you must authenticate") unless $match->{user};

    my $username = $match->{user}->{username};
    my $joinable;
    for my $id (keys $self->{games}->%*) {
      my $game = $self->{games}{$id};
      next if $game->winner;
      next if $game->{players}{$username};
      $joinable = $id;
      last;
    }

    unless ($joinable) {
      my ($max) = sort { $b <=> $a } keys $self->{games}->%*;
      my $id = defined $max ? $max + 1 : 1;
      $self->{games}{ $id } = TTT::Game->new;
      $joinable = $id;
    }

    my $game = $self->{games}{$joinable};
    my %has_player = map {; $_ => 1 } values $game->{players}->%*;
    my @options    = grep {; ! $has_player{$_} } qw(x o);
    $game->{players}{ $username } = $options[ rand @options ];

    return $self->_game_res(
      201,
      [ Location => "/game/$joinable" ],
      $req,
      $game,
    );
  }

  sub game ($self, $req, $match) {
    my $game = $self->{games}{ $match->{game} };

    return mkerr(404 => "no such game") unless $game;

    my $status = 200;

    if ($req->method eq 'PUT') {
      my $move = $self->body_data($req);

      return mkerr(403 => "bogus move") unless $move;

      my $result = $game->play($match->{user}, $move->{where});
         $status = $result == -1 ? 403 : 200;
    }

    return $self->_game_res($status, [], $req, $game);
  }

  sub _game_res ($self, $status, $hdr, $req, $game) {
    my $format = $req->parameters->{format} // 'json';

    if ($format eq 'text') {
      return [
        $status,
        [ @$hdr, "Content-Type", "text/plain", ],
        [ $game->as_text ],
      ];
    } else {
      return [
        $status,
        [ @$hdr, "Content-Type", "application/json", ],
        [ $game->as_json ],
      ];
    }
  }
}

TTT::Web->new->app
