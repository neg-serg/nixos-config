##
# Module: user/nix-maid/apps/supercollider
# Purpose: TidalCycles one-click launch.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.creation or { };
  enabled = cfg.enable or false;

  # SuperDirt and Vowel now come from nix packages (packages/superdirt,
  # packages/vowel) symlinked into SC's default extension dir below — the
  # manual `install-superdirt-quark` step is gone.

  superdirtStartup = ''
    s.options.numBuffers = 1024 * 1024;
    s.options.memSize = 8192 * 64;
    s.options.numWireBufs = 256;
    s.options.maxNodes = 1024 * 64;
    s.options.numOutputBusChannels = 2;
    s.options.numInputBusChannels = 2;
    s.waitForBoot {
      var userSamples = Platform.userHomeDir +/+ "src/art/music/tidal/samples";
      try {
        ~dirt = SuperDirt(2, s);
        // Explicit sample paths — do NOT rely on loadSoundFiles' default
        // "../../Dirt-Samples/*".resolveRelative (it resolves against the
        // document dir, which breaks once SuperDirt lives in the nix store).
        File.mkdir(userSamples);
        // loadSoundFiles expands the glob only for a plain String path,
        // so the stock bank and the user samples dir get separate calls.
        ~dirt.loadSoundFiles("${pkgs.neg.dirt-samples}/share/Dirt-Samples/*");
        if(PathName(userSamples).folders.notEmpty) {
          ~dirt.loadSoundFiles(userSamples +/+ "*")
        };
        -- 16 orbits so Tidal d1..d16 all get a stream (start(port, 0 ! 16));
        -- with 12 orbits, d13-d16 events are dropped by SuperDirt.
        ~dirt.start(57120, 0 ! 16);
        "SUPERDIRT READY".postln;
      } { |err| ("SuperDirt ERROR: " ++ err.what).postln; };
    };
  '';

  bootNoop = ''
    s.options.numOutputBusChannels = 2;
    s.waitForBoot { "SC server ready".postln; };
  '';

  bootTidal = ''
    :set -fno-warn-orphans -Wno-type-defaults -XMultiParamTypeClasses -XOverloadedStrings
    :set prompt ""
    import Sound.Tidal.Boot
    default (Rational, Integer, Double, Pattern String)
    tidalInst <- mkTidal
    instance Tidally where tidal = tidalInst
    :set prompt "tidal> "
    :set prompt-cont ""

    -- ==== Musical helpers ==================================================
    -- Short instrument aliases (sample folder names).
    let k  = sound "bd"      -- kick
        sn = sound "sn"      -- snare
        hh = sound "hh"      -- hi-hat
        cp = sound "cp"      -- clap
        bass = sound "bass"  -- bass synth samples
        tab = sound "tabla"  -- tabla kit

    -- Rhythm phrases (paste into `sound`).
    let fourOnFloor = "bd(4,8) sn(3,8) hh*8"
        techno      = "bd*2 sn(3,8) hh*4"
        halftime    = "bd(2,8) sn(2,8) hh*6"
        jungle      = "bd(3,8) sn(5,8) hh*6"

    -- Random groove generator: re-chooses its phrase every cycle.
    --   d1 $ randomGroove
    let randomGroove = sound (choose ["bd*2 sn*3 hh*4", "bd(3,8) sn(5,8) hh(5,8)", "bd(5,8) hh*6", "bd(2,8) cp(3,8) hh*4"])

    -- Random euclidean kick/snare: `irand` re-rolls each cycle.
    --   d1 $ randomEuclid 8
    let randomEuclid steps = euclid (irand steps) steps $ sound "bd"

    -- Ambient pad on a random minor chord (re-rolls every 4 cycles).
    --   d1 $ ambientPad
    let ambientPad = note (scale "minor" (cat ["c4", "g4", "a4", "f4"])) # sound "superpiano" # room 0.5 # size 0.8 # gain 0.6

    -- ==== Generative helpers (algorithmic composition) ======================
    -- Runtime strings must be parsed explicitly (mini-notation parses only at
    -- IsString coercion), hence `fromString` below.
    import Data.String (fromString)
    import System.Random (mkStdGen, randomRs) -- for the Markov drum chain
    import Data.List (sort) -- for Forte pc normalization

    -- Schillinger resultant: attacks where either generator (periods a, b)
    -- lands, within a*b steps — pure-arithmetic rhythm generator, always a
    -- palindrome.  d1 $ resultant 3 2  →  "bd ~ bd bd bd ~"
    let resultant a b = s (fromString (unwords [ if i `mod` a == 0 || i `mod` b == 0 then "bd" else "~" | i <- [0 .. a * b - 1] ]))

    -- Xenakis sieve: one modulus m, hits where i mod m ∈ residues rs.
    --   d1 $ sieve 3 [0,1]   →  octatonic pulse (residue classes 3₀∪3₁ mod 3)
    let sieve m rs = s (fromString (unwords [ if i `mod` m `elem` rs then "bd" else "~" | i <- [0 .. m - 1] ]))

    -- Colotomy layer (gamelan): one hit at the start of each n-step cycle;
    -- layer several at different speeds for nested modular cycles.
    --   d1 $ slow 4 $ colotom 4 "supergong"             -- gong every 16 steps
    --   d2 $ slow 4 $ (0.5 <~) $ colotom 4 "supermandolin" -- kenong, half-cycle off
    let colotom n nm = s (fromString (unwords [ if i == 0 then nm else "~" | i <- [0 .. n - 1] ]))

    -- Weighted chord progression (Melodique-style: I, IV, V, vi attraction,
    -- weights 4/3/2/2 — a 0th-order Markov choice over scale degrees,
    -- re-rolls every cycle).  d1 $ weightedChords
    let weightedChords = note (scale "minor" (choose [0, 0, 0, 0, 3, 3, 3, 4, 4, 5, 5])) # sound "superpiano" # room 0.4 # gain 0.7

    -- Reich phasing: the same 8-step pattern on two layers, one drifting via
    -- a slightly different tempo (Clapping Music / Piano Phase idiom).
    --   d1 $ phase8
    --   d2 $ phase8 # speed 1.01    -- d2 slowly overtakes d1
    let phase8 = sound "bd*8"

    -- Messiaen mode 2 (octatonic) as semitone numbers from C4 — no scale
    -- definition needed.  d1 $ octatonic
    let octatonic = n "60 61 63 64 66 67 69 70" # sound "superhex" # gain 0.4

    -- ==== More theory-derived helpers =========================================
    -- Messiaen mode 3 (2-1-1-2-1-1...) and whole-tone mode 1 — like octatonic,
    -- other modes of limited transposition.
    --   d1 $ mode3            d1 $ wholeTone
    let mode3 = n "60 62 63 65 66 68 69" # sound "superhex" # gain 0.4
    let wholeTone = n "60 62 64 66 68 70" # sound "superhex" # gain 0.4

    -- Carter metric modulation: tempo ratio.  d1 $ fast (modulate 4 6) $ sound "bd"
    let modulate oldD newD = fromIntegral oldD / fromIntegral newD

    -- Glass additive process: figure grows by `step` notes each cycle,
    -- up to `maxN` notes.  d1 $ glassAdd 4 1  →  1, 2, 3, 4 bd
    let glassAdd maxN step = fastcat [ s (fromString (unwords (replicate n "bd"))) | n <- [1, 1+step .. maxN] ]

    -- Messiaen interversion: palindromic permutation of a rhythmic cell.
    --   d1 $ interversion "bd sn hh cp"
    let interleave (x:xs) (y:ys) = x : y : interleave xs ys
        interleave xs [] = xs
        interleave [] ys = ys
    let interversion nm = s (fromString (unwords (let (a, b) = splitAt (length ws `div` 2) ws in interleave (reverse a) b))) where ws = words nm

    -- L-system (Cantor dust): fractal self-similar rhythm.  d1 $ lSystem 3
    let lstep xs = concatMap (\x -> if x == "bd" then ["bd", "~", "bd"] else ["~", "~", "~"]) xs
    let lSystem n = s (fromString (unwords (iterate lstep ["bd"] !! n)))

    -- Wolfram elementary cellular automaton as a rhythm row: evolve one
    -- row of n cells for n steps, keep only the LAST row (n hits per cycle,
    -- not n²).  d1 $ caRule 110 16  (rule 110 = Class 4 edge-of-chaos)
    let cbit r l c rr = (r `div` (2 ^ (4*l + 2*c + rr))) `mod` 2
    let cstep r xs = [ cbit r (xs !! ((i-1) `mod` length xs)) (xs !! i) (xs !! ((i+1) `mod` length xs)) | i <- [0 .. length xs - 1] ]
    let cell 1 = "bd"
        cell _ = "~"
    let caRow r n = last (take n (iterate (cstep r) (1 : replicate (n-1) 0)))
    let caRule rule n = s (fromString (unwords (map cell (caRow rule n))))

    -- ==== Serialism: Schoenberg 12-tone row ================================
    -- Prime form of a row as pitch-class list; operations P/R/I/RI + transposition.
    --   d1 $ row12 row               -- prime form from C4
    --   d1 $ row12 (transp 3 row)    -- transposed
    --   d1 $ row12 (retr (invert row)) -- retrograde inversion
    let row = [0, 11, 7, 1, 6, 2, 10, 3, 9, 4, 8, 5] :: [Int]
    let transp t = map (\p -> (p + t) `mod` 12)
    let invert = map (\p -> (12 - p) `mod` 12)
    let retr = reverse
    let row12 r = n (fromString (unwords (map show (map (+60) r)))) # sound "superhex" # gain 0.4

    -- ==== Indian talas (rhythmic cycles) ==================================
    -- Clap-based tala cycles: tintal (16), keharwa (8), dadra (6), rupak (7).
    --   d1 $ tala tintal # sound "bd"    -- one cycle per bar
    let tala beats = s (fromString (unwords (replicate (sum beats) "bd")))
        tintal = [4, 4, 4, 4]
        keharwa = [4, 4]
        dadra = [3, 3]
        rupak = [3, 2, 2]

    -- ==== Greek metrical feet =============================================
    -- Short/long cells as ready-made patterns.
    --   d1 $ fast 4 $ iambP      -- u-  (iamb)
    --   d1 $ fast 4 $ trocheeP   -- -u
    --   d1 $ fast 4 $ dactylP    -- -uu
    --   d1 $ fast 4 $ anapestP   -- uu-
    --   d1 $ fast 4 $ spondeeP   -- --
    let iambP = s "~ bd"
        trocheeP = s "bd ~"
        dactylP = s "bd ~ ~"
        anapestP = s "~ ~ bd"
        spondeeP = s "bd bd"

    -- ==== Xenakis & Lutoslawski ==========================================
    -- Poisson-like density: random hits, decaying gain, at tempo k.
    --   d1 $ xenakisDensity 4
    let xenakisDensity k = fast (fromIntegral k) (degradeBy 0.3 (s "bd"))

    -- ==== Markov 1st-order drums ==========================================
    -- True 1st-order Markov chain over bd/sn/hh with a transition matrix,
    -- walked deterministically from a seed. Vary the seed for new grooves.
    --   d1 $ markovGroove 16 42
    let nextState :: String -> Double -> String; nextState st r = if st == fromString "bd" then (if r < 0.6 then "bd" else if r < 0.9 then "sn" else "hh") else if st == fromString "sn" then (if r < 0.4 then "bd" else if r < 0.6 then "sn" else "hh") else (if r < 0.3 then "bd" else if r < 0.5 then "sn" else "hh")
    let markovSeq :: Int -> Int -> [String]; markovSeq n seed = reverse (snd (foldl (\(st, acc) r -> let st' = nextState st r in (st', st' : acc)) (fromString "bd", []) (take n (randomRs (0.0, 1.0) (mkStdGen seed)))))
    let markovGroove n seed = s (fromString (unwords (markovSeq n seed)))

    -- ==== Messiaen: non-retrogradable rhythm + added values ===============
    -- Palindromic durations (symmetric around center).  d1 $ palindur
    let palindur = s "bd ~ bd ~ bd"
    -- Valeur ajoutée: small unit inserted into a regular pattern.
    --   d1 $ addedValue 4     -- bd hh bd hh bd hh bd
    let addedValue n = fastcat (concatMap (\i -> if i < n then [s "bd", s "hh"] else [s "bd"]) [1..n])

    -- ==== 1/f noise melody (fractal) ======================================
    -- Precomputed pink-noise-ish series.  d1 $ fNoise
    let fNoise = n (fromString "60 63 61 64 62 65 63 60 62 66 64 61") # sound "superpiano" # gain 0.4

    -- ==== Perle cyclic sets ===============================================
    -- Alternating interval cycles (mod 12), kept in the 60..71 register.
    --   d1 $ perleCycle 2 3
    let perleCycle a b = n (fromString (unwords (map show (scanl (\x i -> 60 + ((x - 60 + (if even i then a else b)) `mod` 12)) 60 [1..11])))) # sound "superhex" # gain 0.3

    -- ==== Hindemith: Series 1/2 ===========================================
    -- Interval consonance rank (0=most consonant .. 6=tritone) and root side.
    --   d1 $ fast 8 $ note (cat [60, 64, 67]) # sound "superpiano" # gain (fromIntegral (6 - hindemithRank 4) / 6)
    let hindemithRank ic = if ic `mod` 12 == 0 then 0 else if ic `mod` 12 == 7 then 1 else if ic `mod` 12 == 4 then 2 else if ic `mod` 12 == 9 then 3 else if ic `mod` 12 == 2 then 4 else if ic `mod` 12 == 5 then 5 else 6
    let hindemithRoot ic = if hindemithRank ic <= 3 then "low" else "high"

    -- ==== Forte: interval vector + pc normalization =======================
    --   print (icVector [0,1,4])   -- [1,0,1,1,0,0] for 3-3
    --   print (pcCompact [7,11,2]) -- [0,4,9] transposed to 0
    let icVector pc = [ length [ (a - b) `mod` 12 | a <- pc, b <- pc, a > b, (a - b) `mod` 12 == ic ] | ic <- [1..6] ]
    let pcCompact xs = let m = minimum xs in sort (map (\x -> (x - m) `mod` 12) xs)

    -- ==== Messiaen deshi-talas ============================================
    -- Named Indian rhythm cells as accent patterns.  d1 $ talaSound 1
    let deshiTala 1 = "x x ~ x x x ~ x"
        deshiTala 2 = "x ~ x x ~ x x ~"
        deshiTala 3 = "x x x ~ x ~ x x"
        deshiTala _ = "x x x x x x x x"
    let talaHit 'x' = "bd"
        talaHit _ = "~"
    let talaSound n = s (fromString (unwords (map talaHit (deshiTala n))))

    -- ==== Yavorsky: 18 modes (tritone-resolution cells) ===================
    --   d1 $ yavorsky 1
    let yavorsky 1 = n "60 61 62 64 65 66 68 69" # sound "superhex" # gain 0.4
        yavorsky 2 = n "60 62 63 64 66 67 69 70" # sound "superhex" # gain 0.4
        yavorsky 3 = n "60 61 63 64 65 67 68 69" # sound "superhex" # gain 0.4
        yavorsky _ = n "60 62 64 65 67 69" # sound "superhex" # gain 0.4

    -- ==== Kholopova: parametric complex ===================================
    -- [articulation, melody, rhythm, texture, writing] binary flags.
    --   d1 $ holopova [1,0,1,1,0]
    let holopova ps = fast (if ps !! 2 == 1 then 2 else 1) (note (cat [60, 62, 64, 65]) # sound "superpiano" # (if ps !! 0 == 1 then legato 0.9 else legato 0.3) # gain (if ps !! 1 == 1 then 0.8 else 0.5))

    -- ==== Bhatkhande thatas (raga scales) =================================
    --   d1 $ that 3   -- Bhairav
    let that 1 = n "60 62 64 65 67 69 71" # sound "superpiano" # gain 0.5
        that 2 = n "60 62 63 65 67 68 71" # sound "superpiano" # gain 0.5
        that 3 = n "60 61 63 64 66 67 70" # sound "superpiano" # gain 0.5
        that 4 = n "60 61 63 65 66 68 70" # sound "superpiano" # gain 0.5
        that 5 = n "60 62 63 65 67 69 70" # sound "superpiano" # gain 0.5
        that 6 = n "60 61 63 64 66 67 69" # sound "superpiano" # gain 0.5
        that _ = n "60 62 64 65 67 69" # sound "superpiano" # gain 0.5

    -- ==== Maqam ajnas (tetrachords, quarter-tones) ========================
    -- Fractional semitones = quarter tones (24-TET).  d1 $ maqamBayati
    let maqamBayati = n "60 61.5 63 64 66 67.5 69 70" # sound "superhex" # gain 0.4
    let maqamHijaz = n "60 61 63.5 64 66 67 69 70" # sound "superhex" # gain 0.4

    -- ==== Gamelan slendro / pelog (microtonal tunings) ====================
    --   d1 $ slendro   d1 $ pelog
    let slendro = n "60 62.4 64.8 67.2 69.6" # sound "superhex" # gain 0.4
    let pelog = n "60 61.3 63.4 66.1 67.9 70.8 73.2" # sound "superhex" # gain 0.4

    -- ==== Xenakis: boolean algebra over pitch sets (Herma) ================
    -- Set ops as pure functions; herma applies one to two pc sets.
    --   d1 $ herma unionSet   d1 $ herma interSet   d1 $ herma diffSet
    let unionSet a b = foldr (\x acc -> if x `elem` acc then acc else x : acc) [] (a ++ b)
    let interSet a b = [ x | x <- a, x `elem` b ]
    let diffSet a b = [ x | x <- a, x `notElem` b ]
    let herma op = n (fromString (unwords (map show (map (+60) (op [0, 1, 4] [0, 3, 7]))))) # sound "superhex" # gain 0.3

    -- ==== Taneev: movable counterpoint ====================================
    -- Two voices at a fixed vertical interval.  d1 $ taneev 4
    let taneev idx = stack [ n "60 62 64 65", n (fromString (unwords (map show (map (+idx) [60, 62, 64, 65])))) ] # sound "superpiano" # gain 0.5

    -- OSC params (pF, pI, pS, ...) come from Sound.Tidal.Params,
    -- re-exported by Sound.Tidal.Boot — no extra import needed.
    -- Sending to an external synth:
    --   d1 $ sound "bd" # pF "myParam" 0.5
  '';

  # SC class library config: keep default paths (SCClassLibrary + user
  # Extensions dir, where the nix SuperDirt/Vowel/SC3plugins symlinks live)
  # and add no extra include paths.
  sclangConf = ''
    includePaths: []
    excludePaths: []
    postInlineWarnings: false
    excludeDefaultPaths: false
  '';

  # Starter .tidal file for the tidal/ workspace dir.
  scratchTidal = ''
    -- TidalCycles scratch file — press <C-CR> to launch, <M-CR> to send a line
    d1 $ sound "bd sn"
    d1 $ sound "bd(3,8) sn(5,8)" # gain 0.9
    d2 $ sound "hh*4" # pan 0.5
    -- user samples: drop folders into ~/src/art/music/tidal/samples/,
    -- then `d1 $ sound "myname"` (folder name = sound name)
    -- generative helpers (defined in BootTidal.hs):
    --   d1 $ resultant 3 2      d1 $ slow 4 $ sieve 3 [0,1]      d1 $ weightedChords
  '';

  # Multi-layer jam scene: send lines top-to-bottom, each adds a layer.
  # Run `tidalctl demo` to open it with the engine already up.
  demoTidal = ''
    -- ============ TIDAL DEMO JAM ============
    -- Send lines one by one (<M-CR>), each adds a layer.
    -- Start with drums, then bass, then chords, then melody.

    -- 1. Kicks: euclidean pattern (3 hits per 8 steps)
    d1 $ euclid 3 8 k

    -- 2. Snare on the backbeat
    d2 $ euclid 3 8 sn # delay 0.25

    -- 3. Hi-hats: steady 8ths, panned
    d3 $ euclid 4 8 hh # pan 0.5 # gain 0.5

    -- 4. Random groove generator (re-rolls every cycle!)
    d4 $ randomGroove # gain 0.7

    -- 5. Random euclidean kick (irand re-rolls each cycle)
    d1 $ randomEuclid 8

    -- 6. Bass: simple minor riff
    d5 $ note (scale "minor" "c2 d2 e2 g2") # sound "bass" # gain 0.8

    -- 7. Ambient pad on a random minor chord (re-rolls every 4 cycles)
    d6 $ ambientPad

    -- 8. Lead melody: arpeggio
    d7 $ note (arp "up" "c4'maj7") # sound "superpiano" # delay 0.3 # room 0.3

    -- 9. Everything together — add swing
    d1 $ swingBy (1/3) 4 $ euclid 3 8 k

    -- 9a. Schillinger resultant 3×2: palindrome rhythm
    d8 $ resultant 3 2 # gain 0.7

    -- 9b. Xenakis sieve: octatonic pulse (residue classes {0,1} mod 3)
    d9 $ slow 4 $ sieve 3 [0,1] # sound "hh" # gain 0.4

    -- 9c. Weighted chord progression (I/IV/V/vi, Melodique-style)
    d10 $ weightedChords

    -- 9d. Gamelan colotomy: gong + kenong layered at nested speeds
    d11 $ slow 4 $ colotom 4 "supergong"
    d12 $ slow 4 $ (0.5 <~) $ colotom 4 "supermandolin" # gain 0.8

    -- 10. L-system (Cantor dust): fractal rhythm
    d13 $ lSystem 3 # gain 0.6

    -- 11. Wolfram CA rule 110: edge-of-chaos rhythm
    d14 $ caRule 110 16 # sound "cp" # gain 0.5

    -- 12. Messiaen interversion: palindromic cell permutation
    d15 $ interversion "bd sn hh cp" # gain 0.7

    -- 13. Glass additive process: 1 → 4 → 7 bd
    d16 $ glassAdd 4 1 # gain 0.8

    -- 14. Schoenberg 12-tone row (prime form) — serial melody
    --     try also: d8 $ row12 (retr (invert row))   (retrograde inversion)
    d8 $ row12 row # gain 0.5

    -- 15. Indian tala: tintal (16-beat cycle) as an accent layer
    d9 $ tala tintal # sound "tabla" # gain 0.6

    -- 16. Greek metrical feet: iamb + trochee polyrhythm
    d10 $ fast 8 $ iambP # sound "hh" # gain 0.4
    d11 $ fast 8 $ trocheeP # sound "cp" # gain 0.4

    -- 17. Xenakis Poisson density at tempo 6
    d12 $ xenakisDensity 6 # sound "bd" # gain 0.6

    -- 18. Markov 1st-order drums (deterministic walk, seed 42)
    d13 $ markovGroove 16 42 # gain 0.7

    -- 19. Messiaen palindur + added values
    d14 $ palindur # gain 0.5
    d15 $ addedValue 4 # sound "hh" # gain 0.3

    -- 20. 1/f (pink noise) fractal melody
    d16 $ fNoise

    -- 21. Perle cyclic set (alternating +2/+3 semitones)
    d7 $ perleCycle 2 3 # gain 0.4

    -- 22. Hindemith: consonant triad, gain scaled by Series-1 rank
    d8 $ note (cat [60, 64, 67]) # sound "superpiano" # gain (fromIntegral (6 - hindemithRank 4) / 6) # delay 0.3

    -- 23. Messiaen deshi-tala 1 as a tabla accent
    d9 $ talaSound 1 # sound "tabla" # gain 0.5

    -- 24. Yavorsky mode 1 (tritone cell) as a saw melody
    d10 $ yavorsky 1 # gain 0.4

    -- 25. Kholopova parametric complex [articulation=1, melody=0, rhythm=1]
    d11 $ holopova [1, 0, 1, 1, 0] # gain 0.5

    -- 26. Bhatkhande thata 3 (Bhairav) as a scale run
    d12 $ slow 2 $ that 3 # gain 0.5

    -- 27. Maqam bayati (quarter-tones via fractional MIDI)
    d13 $ slow 2 $ maqamBayati # gain 0.4

    -- 28. Gamelan slendro (microtonal tuning)
    d14 $ slow 2 $ slendro # gain 0.4

    -- 29. Xenakis Herma: union of two pc sets as a harmony
    d15 $ herma unionSet # gain 0.4

    -- 30. Taneev movable counterpoint at interval 4
    d16 $ taneev 4 # gain 0.5

    -- 22. Silence everything (hush: <leader>th)
    -- hush
  '';
in
{
  config = lib.mkIf enabled {
    environment.sessionVariables = {
      LD_LIBRARY_PATH = [ "${pkgs.pipewire.jack}/lib" ];
      # Server-side SC3-Plugins UGens (.so) — scsynth ищет их через SC_PLUGIN_PATH
      SC_PLUGIN_PATH = "${pkgs.supercolliderPlugins.sc3-plugins}/lib/SuperCollider/plugins";
    };
    environment.etc = {
      "skel/.config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      "skel/.config/SuperCollider/boot_noop.scd".text = bootNoop;
    };
    users.users.neg.maid.file.home = {
      ".config/SuperCollider/superdirt_startup.scd".text = superdirtStartup;
      ".config/SuperCollider/boot_noop.scd".text = bootNoop;
      ".config/SuperCollider/sclang_conf.yaml".text = sclangConf;
      ".config/tidal/BootTidal.hs".text = bootTidal;
      # SuperDirt classes from the nix package (replaces manual quark install)
      ".local/share/SuperCollider/Extensions/SuperDirt".source =
        "${pkgs.neg.superdirt}/share/SuperCollider/extensions/SuperDirt";
      # Vowel formant tables from the nix package (SuperDirt initVowels needs it)
      ".local/share/SuperCollider/Extensions/Vowel".source =
        "${pkgs.neg.vowel}/share/SuperCollider/extensions/Vowel";
      # SC3-Plugins классы (DynKlank, SwitchDelay, …) — нужны SuperDirt default-synths
      ".local/share/SuperCollider/Extensions/SC3plugins".source =
        "${pkgs.supercolliderPlugins.sc3-plugins}/share/SuperCollider/Extensions/SC3plugins";
      # Tidal workspace: starter file + demo jam + user samples dir
      "src/art/music/tidal/scratch.tidal".text = scratchTidal;
      "src/art/music/tidal/demo.tidal".text = demoTidal;
    };
  };
}
