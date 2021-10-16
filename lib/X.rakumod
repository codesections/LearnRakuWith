# This file contains three types of messages, all of which inherit from Exception and aren't program
# output (so should be printed to STDERR, not STDOUT).  They are namespaced in V (verbose output,
# aka messages), W (warnings - a yellow header), X (exceptions - a red header).

#| A helper role for pretty-printing error messages in color and with contextual info.
role XPretty {
    # compare Rakudo src/core.c/Rakudo/Internals.pm6 line 767
    method red($_)    { $*DISTRO.is-win ?? $_ !!  "\e[31m" ~$_ ~"\e[0m" }
    method yellow($_) { $*DISTRO.is-win ?? $_ !!  "\e[32m" ~$_ ~"\e[0m" }
    
    method fmt-src(&fn, Range :$lines-of-context = (-2..2), Str :$fn-name = &fn.name) {
        (try {
        my @line-range = $lines-of-context + (max(&fn.line - 1, 2));
        
        (@line-range.flat Z &fn.file.IO.lines[@line-range]).map(
            -> ($n, $txt, :$fmt-n = '%4u'.sprintf($n+1) ) {
                when not $txt.defined   { #`[EOF]    last }
                when $n ≠ &fn.line - 1  { "$fmt-n | $txt" }
                my $red-squiggles = do with $txt {
                    S[.* ($fn-name) .*] = ' 'x$0.from ~$.red('^' x$0.chars) ~' 'x .chars-$0.to }
                $.red($fmt-n) ~" | $txt\n" ~"     | " ~$red-squiggles
            }) .join("\n")}) // "    SORRY, could not print source!"
    }
}


## Verbose output ##

class V::LRW::Welcome is Exception does XPretty {
    method message { ( "Welcome to Learn::Raku::With::HtmlBalls.  Start the LearnRakuWith server by sending the\n"
                      ~".server-start message or see the README.md for more info.")
                     .indent: 2 }}

class V::LRW::Start is Exception does XPretty {
    has ($.port, $.host);
    method message { ( "Server now listening on $!host:$!port.  Check it out in your browser!\n\n"
                      ~"When you're done, you can signal the server to stop by pressing ^C (Ctrl+c).\n")
                     .indent: 2 }}

class V::LRW::Exit is Exception does XPretty {
    method message { ("\nExit signal received.  Shutting down now...\n").indent: 2 }}


## Warnings ##

class W::LRW::Timeout is Exception  does XPretty  {
    has &.fn is required;

    method message { ($.yellow("Warning:\n")
                       ~"The :map-fn {if &!fn.name -> $_ { “(&$_) ” }}timed out.  Could it have an infinite loop?\n"
                       ~"Restarting from last known-good state.\n")
                     .indent: 2 }}

class W::LRW::State is Exception does XPretty {
    has &.map-fn is required;
    has $.err is required;

    method message { ($.yellow("Warning:\n")
                       ~"&!map-fn.name() encountered an error:\n" ~ $!err.gist.indent(4) 
                       ~"Restarting from last known-good state.\n") 
                     .indent: 2 }}

class W::LRW::QuickExit is Exception does XPretty {

    method message {
        ($.yellow("Warning:\n")
          ~"Learn::Raku::With exited very quickly.  It's possible that your script is missing a &sleep command.\n")
        .indent: 2 }}


## Exceptions ##

class X::LRW::Socket is Exception does XPretty {
    has ($.host, $.port);
    
    method message { ($.red("Error\n")
                       ~"Could not start the LRW server on $!host:$!port because the address is in use.\n"
                       ~"Maybe another instance of the server is running?\n\n"
                       ~"You can specify a different host or port with the LRW_HOST or LRW_PORT environmental variables.\n")
                     .indent: 2 }}

class X::LRW::TypeCheck::Argument is Exception does XPretty {
    has $!param is built;
    has $!got   is built(:bind);

    multi method message(| where $!param eq 'run') { 
        ($.red("Error:\n")
         ~"The :run parameter expects to receive a Boolean value but it got\n"
              ~($!got.gist ~ "   (which is a {$!got.WHAT.raku ~ (' type object' if !$!got.defined)})")
               .indent(4) ~"\n\n")
        .indent: 2 }

    multi method message(| where $!param eq 'balls') {
        ($.red("Error:\n")
         ~"The :balls parameter expects to either a Ball or a Positional collection of Balls,\n"
          ~"such as an Array of Balls or a List of Balls.  But it got:\n\n"
              ~($!got.gist ~ "   (which is a {$!got.WHAT.raku ~ (' type object' if !$!got.defined)})")
              .indent(4) ~"\n\n"
              ~(if $!got.isa('HtmlBalls::Ball') {
                    "You can create a Ball instance from the Ball type object by calling Ball.new()\n"}))
        .indent: 2 } 
    
    multi method message(| where $!param eq 'map-fn') { 
        ($.red("Error:\n")
          ~"The :map-fn parameter expects to receive a Subroutine or other Callable type but got:\n\n"
              ~($!got.gist ~ "   (which is a {$!got.WHAT.raku ~ (' type object' if !$!got.defined)})")
               .indent(4) ~"\n\n"
          ~"Please provide a function, which should transform input of all existing Balls into\n"
          ~"output of zero or more Balls.  This function will be called 60 times per second.\n")
        .indent: 2 }}

class X::LRW::TypeCheck::Return is Exception does XPretty {
    has &!fn  is built(:bind);
    has $!got is built(:bind);

    method message {
        my $fn-name = &!fn.name || ':map-fn';
        ($.red("Error:\n")
          ~"The function passed to :map-fn must return a Ball or a Positional collection of Balls,\n"
          ~"such as an Array of Balls or a List of Balls.  But the function you provided "
          ~(if &!fn.name -> $_ {"(&$_) "}) ~"returned:\n\n"
              ~$!got.raku.indent(4) ~"\n\n"
          ~(if all $!got.map(* ~~ Cool) {
                "It's possible that you returned some attributes of each Ball instead of the Balls themselves.\n"})
          ~(unless &!fn.file eq '<unknown file>' {"You defined $fn-name in " ~ &!fn.file.IO.absolute 
                                                  ~"\non line &!fn.line():\n\n" 
                                                  ~$.fmt-src(&!fn, :$fn-name) ~ "\n"}))
        .indent: 2
    }}

class X::LRW::Parameter::Unexpected is Exception does XPretty {
    has Capture $.args;

    method message {
        ($.red("Error:\n")
          ~"&learn-raku takes no positional arguments and three named arguments, :run, :map-fn, and :balls.\n"
          ~"However, &learn-raku received the following unexpected arguments:\n\n"
              ~("positional: {$!args.list.map(*.gist)}\n" 
               ~"named:      " ~$!args.hash.map(":" ~*.key.gist)).indent(4) ~"\n")
        .indent: 2 }}

class X::LRW::Parameter::RequiresOne is Exception does XPretty {
    method message { ($.red("Error:\n")
                       ~"&learn-raku requires at least one argument but was called without any")
                     .indent: 2 }}



class X::LRW::NoStatesLeft is Exception does XPretty {
    method message {
        ($.red("Error:\n") ~"No known-good states remaining.  Learn::Raku::With will exit.\n").indent: 2 }}


sub check-params(Capture \unexpected, :$map-fn is raw, :$balls is raw, :$run) is export is hidden-from-backtrace {
    when ? unexpected      { die X::LRW::Parameter::Unexpected.new: :args(unexpected)}
    when $run !~~ Bool
      && $run !~~ Empty    { die X::LRW::TypeCheck::Argument.new:   :param<run>,    :got($run) }
    when $map-fn !~~ Code
      && $map-fn !~~ Empty { die X::LRW::TypeCheck::Argument.new:   :param<map-fn>, :got($map-fn)}
    $map-fn.eager if $map-fn ~~ Seq; # Avoid unthrown errors in Lazy Seqs

    when $balls ~~ Positional and ? all($balls.map: {.isa('HtmlBalls::Ball') & .so})  { Nil }
    when ? $balls.isa('HtmlBalls::Ball') & $balls.so                                  { Nil }
    X::LRW::TypeCheck::Argument.new: :param<balls>, :got($balls)
}

sub checked-return(@balls, :&map-fn) is export is hidden-from-backtrace {
    given try map-fn @balls {
        when Positional & all(.map: {.isa('HtmlBalls::Ball') & .so}) && ?.elems  { $_ }
        when $_ === Nil     {
            my $balls:<?> = try { @balls.map({  map-fn $_ })}; 
            if ? $balls:<?>.elems
                && all($balls:<?>.map: {.isa('HtmlBalls::Ball') & .so})  { $balls:<?>.Array }
            else  { X::LRW::TypeCheck::Return.new: :fn(&map-fn),
                                                   got => $balls:<?>.first(!*.isa('HtmlBalls::Ball')) }}
        default   { X::LRW::TypeCheck::Return.new: :fn(&map-fn), :got($_) }
    }
}
