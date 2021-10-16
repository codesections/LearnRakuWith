use v6.d;
use Cro::HTTP::Router; use Cro::HTTP::Server;
use Cro::HTTP::Router::WebSocket; use Cro::WebApp::Template;
use X::LRW;

unit module HtmlBalls;

class Ball {...}

# The only public concurrency  - everything else is scoped
my $server-cmd = Supplier::Preserving.new;
my ($frame-stream-ready, $server-ready) = (Promise.new, Promise.new);

#| Set up a stream of frames containing Arrays of Balls, and stream them to the $out-to-ws Supplier.
#| Each frame is generated by applying the &map-fn to the Balls in the previous frame; frames are
#| generated at 60fps.  &init-frame-stream accepts messages via the :$frame-stream-cmd Supplier, and
#| responds to :!run (stop running, triggering &done), and :&map-fn / :@balls (change the mapping fn
#| and current Balls, respectively).  &init-frame-stream is also responsible for supervising each
#| frame-stream and restarting any that die or appear to be stuck in a loop.  To successfully kill
#| and bring the streams back up, &init-frame-stream maintains a history of known-good states and
#| can reset the stream to past states.
sub init-frame-stream(Supplier :$cmd, Supplier :output-balls($out-to-ws) --> Promise) is pure {
    my ($new-out-stream, $out-stream) = ($_ , .Supply.migrate) with Supplier.new;

    #| This is the actual stream that applies the user's &map-fn 60× per second.  Its scope is
    #| deliberately limited, both to make killing/restoring it easy and because its hot code.
    sub new-frame-stream(:&map-fn, :@balls where all .map: * ~~ Ball ) is hidden-from-backtrace {
        $new-out-stream.emit: supply {
            whenever Supply.interval(1/60) {
                my $return = checked-return(:&map-fn, @balls);
                @balls = my Ball:D @ = |$return unless $return ~~ Exception;
                emit $return }}
    }

    #        NOTE: This should really be a Persistent Data Structure, once those land.
    #| An Array that makes defensive copies before we let the &map-fn access the (mutable) Balls.
    role CopyingArray { method push(\v)   { callwith v.deepmap:  *.clone }
                        method STORE(\v)  { callwith v.deepmap:  *.clone }
                        method AT-POS(\i) { callwith(i).deepmap: *.clone }}

    my Channel $forward-or-vent .= new;
    start react {
        my $errs-in-a-row = 1;
        my @history does CopyingArray = [{}, ];
        sub update-history(:map-fn(&f), Ball:D :balls(@b), :%prev = @history[*-1] ) {
            @history.push({:map-fn(&f or %prev<map-fn>), :balls[|@b or |%prev<balls>]}) }

        sub revert(Int $steps = 0) is hidden-from-backtrace {
            my $err-count = ++$errs-in-a-row + $steps;
            if $err-count < +@history and (try new-frame-stream(|@history[*-($errs-in-a-row + $steps)])) -> $_ {
                                              start {$_} }
            else { warn X::LRW::NoStatesLeft.new;
                   $server-cmd.emit: %(:exit);
                   done }}

        my ($stop-cmd, $new-state) = (.grep(*<run> === False), .grep(*<map-fn balls>.any.defined)) with $cmd.Supply;
        my Instant $ok-at = now;
        $frame-stream-ready.keep if $frame-stream-ready.status ~~ Planned; # Kept if we've been called before

        whenever $new-state         { update-history(|$_)       andthen start new-frame-stream(|@history[*-1])}
        whenever $out-stream        { when Exception { note $_  andthen revert }
                                      ($ok-at, $errs-in-a-row) = (now, 1);
                                      $forward-or-vent.send: $_ }
        whenever $stop-cmd          { done }
        whenever Supply.interval(1) { when (now - $ok-at > 7) {
                                            warn W::LRW::Timeout.new: :fn(@history[*-1]<map-fn> // sub anon {});
                                            revert 1 }}
    }

    # This handles backpreasure from downstream (e.g., the ws) by dropping the frame.  We don't want
    # to push the backpreasure up to the frame-stream b/c that would slow the calculation of the
    # frames.  We'd rather drop every other frames at 30 fps than show all the frames at 1/2 speed.
    # NOTE: we can still see a slowdown for large numbers of client due to contention for threads.
    start react { whenever $forward-or-vent -> @first {
        my @out = [@first, ];
        while $forward-or-vent.poll -> $_ { @out[0] = $_ }
        $out-to-ws.emit: @out[0]}
    }
    $frame-stream-ready
}


#| The main Cro::Service powering the server.  It gets its own thread and doesn't start until it
#| gets a :run command.  It's mostly just responsible for standing up the Cro server/main stream
#| with any user-supplied configuration.  It also handles stop/restart commands and serves the
#| site's minimal static HTML.
(sub main-server() { start {
    my ($port, $host)  = $*ENV<LRW_PORT LRW_HOST> Z//  <10000 localhost>;
    my ($frame-stream-cmd, $output-balls) = (Supplier::Preserving.new, Supplier.new);

    my $output-data = $output-balls.Supply.map: {
        [ .map: -> Ball (:$x, :$y, :$radius, :$color) { # <-- is done here for performance with many clients:
              %( x      => $x      ÷ 100,               #     It's more efficent to tranform each Ball
                 y      => $y      ÷ 100,               #     into a Hash (w/ scaled numerical values)
                 radius => $radius ÷ 100,               #     *once* and then clone the Hashes for each
                 color  => $color).clone} ] };          #     ws client rather than to do the .map later

    my $cro = Cro::HTTP::Server.new: :$host:$port,
                  application => route { get ->      { template %?RESOURCES<main.crotmp>.IO, %(:$port) }
                                         get -> 'ws' { web-socket :json, {ws-handler $_, :$output-data}}};

    react {
        my $on = False; # We need to track this ourselves b/c Cro doesn't tell us if it's running
        my (&map-fn, Ball @balls) = (sub id(\a) {a}, Ball.new);

        multi server(:on($)!) is hidden-from-backtrace {
            with try IO::Socket::INET.new: :listen:localhost($host):localport($port) {
                 .close } # Cro doesn't rethrow failed listen; see croservices/cro-core#13
            else { die X::LRW::Socket.new: :$port:$host }
            $cro.start;
            note V::LRW::Start.new: :$host, :$port;
            await init-frame-stream(:cmd($frame-stream-cmd), :$output-balls);
            $frame-stream-cmd.emit: %(:&map-fn, :@balls);
            $on = True;
        }
        multi server(:off($)!) is hidden-from-backtrace {
            $on = False;
            note V::LRW::Exit.new;
            $cro.stop }

        my ($time) = (now, False);
        END { note W::LRW::QuickExit.new if ($on and now - $time < 5) }

        whenever $server-cmd {
            when .<run> === False          { unless not $on { server :off }}
            when .<run> === True           { unless $on     { server :on  }}
            when .<exit> === True          { server :off; # don't exit the REPL vvvv
                                             exit 1 unless $*PROGRAM-NAME eq 'interactive' }
            when ? (.<map-fn> || .<balls>) {
                if $on { $frame-stream-cmd.emit: $_}
                else   { (&map-fn, @balls) = ((.<map-fn>//&map-fn), |(.<balls>//@balls)) }}}

        whenever signal SIGINT { unless ! $on { server :off };  exit }
        $server-ready.keep;
    }

}})();

#| The WebSocket handler, which basically just listens for new frames to send to the client, scales
#| those frames based of the screen-size info clients send over the ws, and forwards the frames.
#| The interaction between the ws-handler and the output-frame stream is designed to prevent either
#| from blocking the other, even with significant backpreasure.
sub ws-handler($client-msg, :output-data($input)) {
    # This ends up being some of the hottest code, so it's worth focusing on perf here – which is why
    # the code below is more procedural/mutating and why it limits Blocks (which create significant
    # GC pressure, even in constructs like `if { }`).
    supply {
        my ($width, $height);
        whenever $client-msg { ($width, $height) = .body.result<width height> if .is-text }
        whenever $input -> @balls {
            $( $(.<x> ×= $width; .<y> ×= $height; .<radius> ×= min($width, $height)) for @balls;
               emit @balls
             ) unless ! $width.defined }}
}

await $server-ready;
#| HtmlBalls' only exported function, and the way for a user to start the server (with the :run
#| command), stop the server (with :!run), set the current Balls (with :@balls), or set the current
#| mapping function (with :&map-fn)
sub learn-raku(:$run = Empty, :$map-fn = Empty, :$balls = Empty, |c) is export {
    with check-params(:$map-fn, :$balls, :$run, c) { if $_ ~~ Exception { die $_ } }
    $server-cmd.emit: {:$run}  with $run;
    when ($run, $map-fn, $balls).all ~~ Any:U { die X::LRW::Parameter::RequiresOne.new }
    $server-cmd.emit: %(|(:map-fn($_) with $map-fn), |(:balls(my Ball @ = |$balls) if $balls)) }

#| A mutable value object that determines the :color, :radius, and :x/:y coordinates of a Ball.  The
#| numerical properties are all percentages of the screen.
class Ball is export {
    (subset Positive of Real where * ≥ 0).^set_name('a positive Numeric');
    has Str      $.color  is rw = "rgb({pick ^256:}, {pick ^256:}, {pick ^256:})";
    has Positive $.radius is rw = rand × 8 + 2;
    has Numeric  $.x      is rw = rand × 100;
    has Numeric  $.y      is rw = rand × 100;

    multi method gist(::?CLASS:D:) { # A slightly hacky line to clean up the debug output
        $.^name ~".new($_)" with $.Capture.kv.duckmap(*.round: .01).pairup.sort».gist.join: ', ' }
}