# Sokoban

A complete little sokoban built on `flix_game_engine`, written as the
worked example of the **Worldline architecture**: one immutable World, a
pure `tick`, projections for the screen, the UI and the ear — and a
Worldline of past Worlds that makes unlimited undo two function calls.

![One full lap of the game](gallery/full_clear.gif)

Slide-based movement, rewind with a spinning alarm clock, two levels, a
title and CLEAR page declared in `ui.json` (hot-reload with F1), confetti
without a particle system, and four procedurally generated sound effects.

## Run

From the repository root, distribute the engine libraries once:

```sh
make sync
```

Then, in this directory (the first test run also bakes the generated
assets — sounds and gallery):

```sh
java -XstartOnFirstThread -jar bin/flix.jar test
java -XstartOnFirstThread -jar bin/flix.jar run
```

Arrows move, Z rewinds, Enter turns pages, X abandons a level, F1 reloads
the UI Specs, Esc quits.

## Learn

The game is built chapter by chapter in the tutorial — one concept at a
time, no prior Flix required:

- [TUTORIAL.md](TUTORIAL.md) (English)
- [TUTORIAL.ja.md](TUTORIAL.ja.md) (日本語)

Every screenshot and GIF above is a test artifact: `flix test` regenerates
the whole [gallery](gallery/index.html), replays the shipped solutions of
both levels, and pins their outcomes.
