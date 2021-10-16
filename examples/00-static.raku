use Learn::Raku::With::HtmlBalls;

my @balls = [
    Ball.new: radius => 47, x => 50, y => 50, color => <yellow>;
    Ball.new: radius => 8,  x => 40, y => 28;
    Ball.new: radius => 8,  x => 60, y => 28;
    Ball.new: radius => 20, x => 50, y => 69, color => <#32383f> ];

learn-raku :@balls;
learn-raku :run;

sleep;
