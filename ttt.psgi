#!perl
use rjbs;

use JSON ();
use Plack::Request;

my $JSON = JSON->new->utf8->canonical;

package TTT::Game {
  sub new ($class) {
    bless {
      next  => 'x',
      board => [ 0 .. 8 ],
    } => $class;
  }

  sub next_player ($self) { $self->{next} }

  sub play ($self, $who, $where) {
    return -1 if $self->winner;
    return -1 unless defined $who and defined $where;
    return -1 unless $who eq $self->next_player;
    return -1 unless $where =~ /\A[0-8]\z/;
    return -1 unless $self->{board}[$where] eq $where;

    $self->{next} = $self->{next} eq 'x' ? 'o' : 'x';
    $self->{board}[$where] = $who;

    return 1 if $self->winner;

    return 0;
  }

  sub winner ($self) {
    return $self->{winner} //= sub {
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

    if (my $winner = $self->winner) {
      $str .= qq{\nThe winner is: $winner\n"};
    }

    return $str;
  }
}

sub ($env) {
  state $GAME;
  $GAME = TTT::Game->new if ! $GAME or $GAME->winner;

  my $req  = Plack::Request->new($env);
  my $body = $req->raw_body;
  my $move = $body ? $JSON->decode($body) : {};

  my $result = $GAME->play($move->{who}, $move->{where});
  my $status = $result == -1 ? 403 : 200;

  my $format = $req->parameters->{format} // 'json';

  if ($format eq 'text') {
    return [
      $status,
      [ "Content-Type", "text/plain" ],
      [ $GAME->as_text ],
    ];
  } else {
    return [
      $status,
      [ "Content-Type", "application/json" ],
      [ $GAME->as_json ],
    ];
  }
}
