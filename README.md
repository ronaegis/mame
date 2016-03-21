MAME with faster HLSL pipeline
===

This branch is based off MAME 0.161 and has modifications done in the Direct3D HLSL renderer.

For each rendered frame, the default MAME HLSL pipeline has about 7 to 9 passes such as NTSC, color convolution, prescaling, phospor, bloom, etc... Disabling the effects though configuration does not prevent MAME from perfoming all those passes.

These modifications disable all HLSL processing effects, EXCEPT for the scanline and pincushion effects contained in "hlsl/post.fx". This gets down the number of HLSL FX passes to just 1.

This helps a lot on computers with low end graphics cards, while retaining the pincushion and scanline effects.

Running MAME 0.161:
```
# mame gng -str 60 -nothrottle
Average speed: 239.48% (59 seconds)
```

Running MAME 0.161 with faster HLSL pipeline:
```
# mame gng -str 60 -nothrottle
Average speed: 529.79% (59 seconds)
```

===

What is MAME?
=============

MAME stands for Multiple Arcade Machine Emulator.

MAME's purpose is to preserve decades of video-game history. As gaming technology continues to rush forward, MAME prevents these important "vintage" games from being lost and forgotten. This is achieved by documenting the hardware and how it functions. The source code to MAME serves as this documentation. The fact that the games are playable serves primarily to validate the accuracy of the documentation (how else can you prove that you have recreated the hardware faithfully?).

What is MESS?
=============

MESS (Multi Emulator Super System) is the sister project of MAME. MESS documents the hardware for a wide variety of (mostly vintage) computers, video game consoles, and calculators, as MAME does for arcade games.

The MESS and MAME projects live in the same source repository and share much of the same code, but are different build targets.

How to compile?
=============

If you're on a *nix system, it could be as easy as typing

```
make
```

for a MAME build, or

```
make TARGET=mess
```

for a MESS build (provided you have all the [prerequisites](http://forums.bannister.org/ubbthreads.php?ubb=showflat&Number=35138)).

For Windows users, we provide a ready-made [build environment](http://mamedev.org/tools/) based on MinGW-w64. [Visual Studio builds](http://wiki.mamedev.org/index.php?title=Building_MAME_using_Microsoft_Visual_Studio_compilers) are also possible.

Where can I find out more?
=============

* [Official MAME Development Team Site](http://mamedev.org/) (includes binary downloads for MAME and MESS, wiki, forums, and more)
* [Official MESS Wiki](http://www.mess.org/)
* [MAME Testers](http://mametesters.org/) (official bug tracker for MAME and MESS)
