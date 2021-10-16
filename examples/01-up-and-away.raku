use Learn::Raku::With::HtmlBalls;

learn-raku :balls(Ball.new: :y(100)),
           :map-fn({.y -= .05; $_})
           :run;

sleep;
