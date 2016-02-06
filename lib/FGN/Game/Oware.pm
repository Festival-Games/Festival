use rjbs;
package FGN::Game::Oware;

use JSON;
my $JSON = JSON->new->utf8->canonical;

sub create_game ($class, $arg) {
  my $game = {
    next  => 'n',
    board => [ (4) x 12 ],
    score => { n => 0, s => 0 },
    players => { n => undef, s => undef },
  };

  my @options = keys $game->{players}->%*;
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

my %INDEX = ( f => 11, e => 10, d =>  9, c =>  8, b =>  7, a =>  6,
              A =>  0, B =>  1, C =>  2, D =>  3, E =>  4, F =>  5 );

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

  return { error => "bogus play" }
    unless defined $where && $where =~ /\A[A-Fa-f]\z/;

  my $index = $INDEX{ $where };

  return { error => "that's not your cup!" }
    if ($game->{next} eq 'n' && $index < 6)
    || ($game->{next} eq 's' && $index > 5);

  my $board = $game->{board};
  my $n = $board->[$index];

  return { error => "cup $where is empty" } unless $n > 0;

  my $pos = $index;
  while ($n--) {
    $pos = ($pos + 1) % 12;
    $board->[$pos]++;
  }

  # XXX simplified rules because testing -- rjbs, 2016-02-05
  if ($board->[$pos] == 3 or $board->[$pos] == 2) {
    $game->{score}{ $game->{next} } += $board->[$pos];
    $board->[$pos] = 0;
  }

  $game->{next} = $game->{next} eq 'n' ? 's' : 'n';

  if ($game->{score} > 10) {
    $game->{winner} = $player;
    $game->{over} = 1; # XXX true
    delete $game->{next};
  }

  return {
    game => $game,
  };
}

sub as_json ($self, $game) {
  $JSON->encode($game);
}

sub as_text ($self, $game) {
  my $board = $game->{board};
  my $str   = q{};

  $str .= "f  e  d  c  b  a\n";
  $str .= sprintf "%-2i %-2i %-2i %-2i %-2i %-2i\n", $board->@[ 11, 10, 9, 8, 7, 6 ];
  $str .= sprintf "%-2i %-2i %-2i %-2i %-2i %-2i\n", $board->@[  0,  1, 2, 3, 4, 5 ];
  $str .= "A  B  C  D  E  F\n";

  for my $pos (sort keys $game->{players}->%*) {
    my $player = $game->{players}{$pos} // '(nobody)';
    $str .= "$pos: $player\n";
  }

  if (my $winner = $game->{winner}) {
    $str .= qq{\nThe winner is: $winner\n};
  } elsif (my $next = $game->{next}) {
    $str .= qq{\nNext to play is: $next\n};
  } else {
    $str .= qq{\nWaiting on players...\n};
  }

  return $str;
}

1;
