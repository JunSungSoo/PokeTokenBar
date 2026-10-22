# Offline battle text catalog

`catalog.json` covers all 559 generation-V moves, all 649 species, generation-V abilities and types in every supported app language: Korean, English, Japanese, Spanish, French, Portuguese and Russian. It is presentation data; the pinned simulator still controls mechanics, current stats, power, type and category.

Sources: [PokéAPI CSV data](https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv) (`move_names`, `move_flavor_text`, `pokemon_species_names`, `ability_names`, `type_names`, `version_groups`) and Pokémon Showdown 0.11.11's generation-V text. Source CSV SHA-256 hashes are in `source-sha256.json`. Pokémon names and original game text belong to their respective rights holders.

Collection loadout tooltips include move descriptions, Gen V power, base PP, type, category and
base accuracy (numeric percentage or always-hit),
plus descriptions for all 164 Gen V abilities. Ability descriptions use `ability_flavor_text`
with the same BW2/nearest-version language preference; English descriptions and move metadata
come from the pinned Gen V simulator. Missing Portuguese/Russian ability descriptions use the
same local preparation-time translation pipeline. Tooltips require no runtime network access.

Descriptions prefer BW2, then the nearest available game text in the same language. English text uses the simulator's generation-V explanation. Missing Portuguese and Russian strings were translated at preparation time with local Argos Translate 1.9 models and CTranslate2; these are app translations, not claimed official translations. Portuguese species use international proper names. Russian retained Latin species names were transliterated. Common demonstration names/descriptions were reviewed explicitly. No translation model, network translation service, API key or language-pack download is needed in the app. Unknown entries receive a localized unavailable label, never an English fallback.

To regenerate, prepare the CSV files in a working directory and run `node scripts/export-battle-text.cjs > /path/to/csv-directory/engine-text.json`, extract the official [Argos models](https://github.com/argosopentech/argospm-index) `translate-en_pt-1_9` and `translate-en_ru-1_9`, install `ctranslate2` and `sentencepiece` in a temporary Python environment, and run:

```sh
python scripts/prepare-battle-text.py --source /path/to/csv-directory --models /path/to/extracted-models
```

The generator preserves CSV translations, fills only missing locales, and rejects incomplete language coverage. Generation is a development operation, not part of application launch or a normal build.
