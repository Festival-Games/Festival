use rjbs;
package FGN::Game::TTT;

use JSON;
my $JSON = JSON->new->utf8->canonical;

sub error ($msg) {
  return { result => { error => $msg } };
}

sub _renderer_for ($self, $arg) {
  return 'as_text' if $arg->{format} // 'text' eq 'text';
  return 'as_json' if $arg->{format} eq 'json';
  return;
}

sub create_game ($class, $arg) {
  return error("can't render requested format")
    unless my $method = $class->_renderer_for($arg);

  my $game = {
    next  => 'x',
    board => [ (undef) x 9 ],
    players => { o => undef, x => undef },
  };

  my @options = keys $game->{players}->%*;
  $game->{players}{ $options[ rand @options ] } = $arg->{player_id};

  return {
    result => $class->$method($game),
    update => {
      game     => $game,
      openings => { $game->{players}->%* },
    },
  };
}

sub join_game ($class, $arg) {
  return error("can't render requested format")
    unless my $method = $class->_renderer_for($arg);

  my $game = $arg->{game};

  my @options = grep {; ! defined $game->{players}{$_} }
                keys $game->{players}->%*;

  return error("game is full") unless @options;

  $game->{players}{ $options[ rand @options ] } = $arg->{player_id};

  return {
    result => $class->$method($game),
    update => {
      game     => $game, # make dumb hash
      openings => @options > 1 ? { $game->{players}->%* } : undef,
    }
  };
}

sub play ($self, $arg) {
  return error("can't render requested format")
    unless my $method = $self->_renderer_for($arg);

  my $player = $arg->{player_id};
  my $game   = $arg->{game};
  my $move   = $arg->{move};
  my $where  = $move->{where};

  return error("game is ended") if $game->{over};

  return error("game not yet begun")
    if grep {; ! defined } values $game->{players}->%*;

  return error("not your turn")
    unless $game->{players}{ $game->{next} } eq $player;

  return error("bogus play") unless defined $where && $where =~ /\A[0-8]\z/;

  return error("space already claimed") if defined $game->{board}[$where];

  $game->{board}[$where] = $game->{next};
  $game->{next} = $game->{next} eq 'x' ? 'o' : 'x';

  if (my $winner = $self->winner($game)) {
    $game->{winner} = $winner;
    $game->{over} = 1; # XXX true
    delete $game->{next};
  } elsif (9 == grep {; defined } $game->{board}->@*) {
    $game->{over} = 1; # XXX true
    delete $game->{next};
  }

  return {
    result => $self->$method($game),
    update => {
      game => $game,
    },
  };
}

sub winner ($self, $game) {
  my @board = $game->{board}->@*;
  no warnings 'uninitialized';
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
  my $json = $JSON->encode($game);
  return { ok => 1, content_type => 'application/json', content => $json };
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
    my $player = $game->{players}{$pos} // '(nobody)';
    $str .= "$pos: $player\n";
  }

  if (my $winner = $game->{winner}) {
    $str .= qq{\nThe winner is: $winner\n};
  } elsif ($game->{over}) {
    $str .= qq{\nThe game has ended in a draw.\n};
  } elsif (my $next = $game->{next}) {
    $str .= qq{\nNext to play is: $next\n};
  } else {
    $str .= qq{\nWaiting on players...\n};
  }

  return { ok => 1, content_type => 'text/plain', content => $str };
}

1;
