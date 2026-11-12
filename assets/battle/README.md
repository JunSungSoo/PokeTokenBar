# Battle UI captures

`doubles-shared-ground.png` and `doubles-one-survivor.png` are captures of the
production `BattleView` using seeded, local engine test battles with Gyarados and
Charizard. The survivor example has no available reserves. These fixtures use the
supported six-member challenge checkpoint format; they do not contain player data.

`fixed-sprite-sizes.png` renders the production native sprite stages to compare
Pidgey, Pikachu, Raichu, both Mega Raichu forms and Charizard in both facings.

Regenerate with `BattleSharedGroundTests` and
`BattleVisibleSizingTests.testSmallSpeciesAndMegaBodyHeightsStayDistinctAndRenderReference`.

`challenge-surrender-only.png` captures the production doubles challenge header in a
local test battle. Surrender replaces the former in-battle Save and exit button.
