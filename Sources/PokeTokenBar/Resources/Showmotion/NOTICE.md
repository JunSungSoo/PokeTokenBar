# Original Showmotion effects

Source: https://github.com/shogun-drei/Showmotion
Pinned commit: `76aaa0b2ae4f3fbe49a4024ae2b6521038cf6d50`.
Author/project: shogun-drei / Showmotion. Original README and source headers are retained.
The reviewed upstream tree does not contain a top-level redistribution license; do not
describe the original effect assets as MIT/CC0 or infer a grant from the extension being free.
Three.js files retain their MIT headers; Effekseer runtime headers are retained as supplied.

The nine `.efkwgd` effects, WASM runtime, Three.js renderer and bloom shaders are original
bytes, verified against the pinned Git blobs by `scripts/prepare-showmotion.py` and recorded
in `source-sha256.json`. `engine.js` is the untouched original. `ptb-engine.js` is a generated
adapter which exposes runtime handles/statistics, pauses rendering when idle, reports errors,
and uses untransformed DOM dimensions. `bridge.js`, `index.html` and `server.cjs` are native-app
integration code. They do not load or replace Pokémon sprites.

The native host serves these bundled files on a random token-protected 127.0.0.1 URL because
WebGPU needs a trustworthy origin. No external server or runtime download is required.
Original foreground/background contexts, camera, GPU effect data and bloom are used. The
effect-only stage maps to the existing Pokémon anchors; rotation follows the attacking side.
The host waits for visibility stabilization and stops drawing on completion or disappearance.

Original support is exactly: Swords Dance, Moonblast, Mystical Fire, Shadow Ball, Will-O-Wisp,
Psychic, Hydro Pump, Gunk Shot, Flower Trick. BW2 move legality remains unchanged, so the six
generation-V-or-earlier moves are available in actual BW2 battles. Other moves, charging,
misses, Reduced Motion, unsupported WebGPU and failed runtime initialization retain native
fallback behavior. A `Showmotion` badge appears during original playback; successful playback
requires actual positive particle and GPU draw counts, not merely runtime readiness.

Development verification: `scripts/ShowmotionValidation.swift` plays the originals in a real,
visible NSApplication window and records per-move counts. A hidden WebView cannot prove GPU
playback; the normal XCTest snapshot suite verifies native fallbacks, while the GPU validation
and interactive battle preview verify original effects separately.
