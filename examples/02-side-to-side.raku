use Learn::Raku::With::HtmlBalls;

enum Directions <Left Right>;
multi side-to-side($single-ball, $current-direction is rw, :$speed = 1) {
    if $single-ball.x > 100        { $current-direction = Left   }
    if $single-ball.x <  0         { $current-direction = Right  }
    if $current-direction ~~ Right { $single-ball.x    += $speed }
    else                           { $single-ball.x    -= $speed }
}

multi side-to-side(@balls, :$speed = 1) {
    state @directions-per-ball;
    for @balls -> $ball {
        state $index = 0;
        @directions-per-ball[$index] //= Right;
        side-to-side $ball, @directions-per-ball[$index];
        $index++;
    }
    return @balls
}

learn-raku :balls[ Ball.new(:y(10), :x(10)),  Ball.new(:y(20), :x(20)),
                   Ball.new(:y(30), :x(30)),  Ball.new(:y(40), :x(40)),
                   Ball.new(:y(50), :x(50)),  Ball.new(:y(60), :x(60)),
                   Ball.new(:y(70), :x(70)),  Ball.new(:y(80), :x(80)),
                   Ball.new(:y(90), :x(90))],
           :map-fn(&side-to-side);


learn-raku :run;

sleep;
