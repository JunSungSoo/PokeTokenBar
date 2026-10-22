# Offline move effect data

Source: Pokémon Showdown client, commit
`ab4b77b8f3a5712e8fbe03ce106ef2b70a874fdb`.
https://github.com/smogon/pokemon-showdown-client

The move animation table (`battle-animations-moves.ts`) declares CC0-1.0.
The shared animation file (`battle-animations.ts`) declares MIT and states that most of the
file and the fx images are CC0, with named asset exceptions. Attribution: Guangcong Luo and
Pokémon Showdown contributors. See the pinned source for individual image creator credits.

We bundle the selected fx images and derived effect-only timing data, not the browser client
or Pokémon sprite assets. `lightning.png`, `icicle.png`, `bone.png`, `rocks.png`, `rock1.png`
and `rock2.png` are excluded; the native renderer draws its own vectors in those cases.
Native fallback effects are original. The separate `Showmotion` resource folder provides nine
original GPU effects; see its NOTICE and pinned source manifest for that integration.

These Showdown animations are shared across generations; `generation: null` records that fact.
Move introduction generation is not an animation's generation. The resolver checks explicitly
tagged generation variants in order 5, 9, 8, 7, 6, 4, 3, 2, 1, then uses the shared recipe.

Regeneration (development only; runtime/builds use checked-in resources): install a working
esbuild in a temporary directory if the battle engine's optional esbuild binary is omitted,
then run `PTB_EFFECT_ESBUILD=/absolute/path/to/node_modules/esbuild node scripts/export-battle-effects.cjs`.
The generator downloads pinned sources and textures. `source-sha256.json` records their hashes.
It excludes Pokémon animation/afterimage operations. Moves whose upstream animation contains
only sprite movement or backdrop changes use native type/category effects so they remain visible.
Two non-finite source particles (division by zero in Spin Out and Matcha Gotcha) are discarded
and reported in the catalog; all exported coordinates must remain finite.

MIT license for the shared animation source:

Copyright (c) Pokémon Showdown contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
