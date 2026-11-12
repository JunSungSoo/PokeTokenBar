# Fixed battle sprite sizes

Display sizes are points, independent of Retina resolution. The same species/form
and facing has the same dimensions in singles, doubles, either player's perspective,
and every entry/recall/switch/Mega presentation scene. Opponents, reserves, battle turn,
and window width never change that size.

Use the pinned `pokemon-heights.json` height and original front/back animation bounds.
The nominal body height is `80 * sqrt(heightInMetres)`. Up to 96 points use that height;
above it use `96 + 16 * (1 - exp(-(height - 96) / 60))`, approaching 112 points.
Normalize using the larger front/back **height**, then cap the larger front/back width
at 177 points with one shared scale. Preserve aspect ratio and the original front/back
height differences. Never independently fit each GIF frame.

This gives Pidgey about 44 points high, Pikachu 50–51, Raichu 71–72, Mega Raichu X
74–81 and Mega Raichu Y 80. A long tail no longer forces Mega Raichu's body down to
roughly half its previous height. Charizard is about 90–98 points high. Very large
species use the bounded curve and width cap instead of shrinking other battlers.

`PokeRogueSpriteSizes.battleSize` is the shared native/player size authority.
`BattleSpriteSizing.forBattle` always returns camera scale 1. Slot widths remain
282/189 points and battlefield heights remain 351/299 for singles/doubles. Max sprite
height 112 plus foot inset 11 fits the smaller 125-point doubles row.

Authored attack squash, entry release growth and Mega transition effects may animate
size temporarily. After playback, both rendering paths return to the same fixed
species/form dimensions. A permanent form change may change that Pokemon's dimensions;
it never changes another Pokemon's size.

Doubles draws one shared ground surface per side. Individual battler stages keep their
animation anchors but suppress their own ground. The shared surface spans both visible
sprite widths plus their 12-point gap and up to 16 points of margin on each edge. Clamp
its width and center inside the pair's layout so wide forms cannot cover the HP cards.
A side with one living displayed battler uses the same rule with that battler's width.
Fainted battlers keep their slot indices for requests and animation anchors but are
hidden; neither their width nor their empty slot contributes to the surface. Keep the
surface under the survivor rather than recentering the survivor into another slot.
If both slots are fainted, draw no surface.
