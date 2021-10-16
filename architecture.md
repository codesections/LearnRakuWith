Here's a high-level overview of how Learn::Raku::With works:

 - The `learn-raku` function accepts user input and
   [emits](https://docs.raku.org/language/control#supply/emit) appropriate commands into the
   `$server-cmd` [Supply](https://docs.raku.org/language/concurrency#Supplies).
 - These commands are handled by the `main-server` function, which starts/stops a Cro server as
   needed and creates a `frame-stream` to produce new output.  Each `frame-stream` runs its own loop
   (basically the equivalent of a game loop, if you're familiar with game programming) by applying
   the user-supplied `map-fn` to the current Balls 60 times every second.
 - Because the `frame-stream` is applying user-written functions, it's possible for it to crash or
   produce invalid output.  To handle this, we maintain a list of past known-good states and can
   kill/reset any `frame-stream` that gets itself into a bad state (this uses the "let it crash"
   pattern for building resilient concurrent systems, borrowed from
   [Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language)) – and, incidentally, I'm
   really excited about how well Raku's concurrency system fits with Erlang techniques).
 - Because the `frame-stream` is generating frames at 60 fps, it's possible for it to generate
   frames faster than we can send them to the browser.  Raku's Supplies deal with this by creating
   [backpreasure](https://6guts.wordpress.com/2017/11/24/a-unified-and-improved-supply-concurrency-model/)
   – that is, by slowing down the generation of new values.  This is normally what you want, but for
   us it'd mean that any lag would result in the Balls _moving_ slower.  We'd rather drop frames,
   (even 30 fps is basically OK), so we use a [Channel](https://docs.raku.org/type/Channel) to
   accept frames and then discard any that the browser isn't ready for. 
 - Separately, Cro has accepted incoming connections for us and established a WebSocket connection
   to each client.  Each connection requests frames from the `frame-stream`, scales them based on
   info it gets from the browser about its current screen size, and then sends some JSON describing
   the Ball.
 - The browser receives the JSON, parses it, and displays a ball every time the browser is ready to
   display another [animation
   frame](https://developer.mozilla.org/en-US/docs/Web/API/window/requestAnimationFrame).
