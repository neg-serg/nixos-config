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
    let fourOnFloor = "bd(4,8) sn(3,8) hh*8"  -- syncopated snare (3-of-8), not a backbeat
        techno      = "bd*2 sn(3,8) hh*4"
        halftime    = "bd(2,8) sn(2,8) hh*6"
        jungle      = "bd(3,8) sn(5,8) hh*6"

    -- Random groove generator: one phrase per cycle via randcat (choose over
    -- strings would be fine here too, but randcat keeps phrases intact).
    --   d1 $ randomGroove
    let randomGroove = randcat [ s "bd*2 sn*3 hh*4", s "bd(3,8) sn(5,8) hh(5,8)", s "bd(5,8) hh*6", s "bd(2,8) cp(3,8) hh*4" ]

    -- Random euclidean kick: `irand` re-rolls each cycle; k in [2, steps]
    -- so we never get a dead (0-hit) cycle.  d1 $ randomEuclid 8
    let randomEuclid steps = euclid (irand (steps-1) + 2) steps $ sound "bd"

    -- Ambient pad: random chord degree re-rolled each cycle (choose over scale
    -- degrees), not a fixed cat — the old comment claimed randomness that
    -- wasn't there.  d1 $ ambientPad
    let ambientPad = note (scale "minor" (choose [0, 4, 5, 7])) # sound "superpiano" # room 0.5 # size 0.8 # gain 0.6

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

    -- Weighted chord progression in C minor: i, iv, v, VI with weights 4/3/2/2
    -- (0th-order Markov over chords, re-rolled each cycle). NB: `scale` gives
    -- single notes, not chords — use chord names via mini-notation instead.
    --   d1 $ weightedChords
    let weightedChords = n (cat (concatMap (\(c, w) -> replicate w c) [("c4'minor", 4), ("f4'minor", 3), ("g4'minor", 2), ("ab4'major", 2)])) # sound "superpiano" # room 0.4 # gain 0.7

    -- Reich phasing: the same 8-step pattern on two layers, one drifting via
    -- a slightly different tempo (Clapping Music / Piano Phase idiom).
    --   d1 $ phase8
    --   d2 $ fast 1.01 $ phase8    -- d2 slowly overtakes d1 (Reich phasing;
    --                                `speed` would change pitch, not timing)
    let phase8 = sound "bd*8"

    -- Messiaen mode 2 (octatonic) as semitone numbers from C4 — no scale
    -- definition needed.  d1 $ octatonic
    let octatonic = n "60 61 63 64 66 67 69 70" # sound "superhex" # gain 0.4

    -- ==== More theory-derived helpers =========================================
    -- Messiaen mode 3 (2,1,1 repeat: C D Eb F G Ab Bb B — 9 tones) and
    -- whole-tone mode 1.  d1 $ mode3   d1 $ wholeTone
    let mode3 = n "60 62 63 65 66 68 69 71 72" # sound "superhex" # gain 0.4
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
    -- Poisson-like density: random hits at tempo k, ~30% dropped (degradeBy).
    --   d1 $ xenakisDensity 4
    let xenakisDensity k = fast (fromIntegral k) (degradeBy 0.3 (s "bd"))

    -- ==== Markov 1st-order drums ==========================================
    -- True 1st-order Markov chain over bd/sn/hh with a transition matrix,
    -- walked deterministically from a seed. Vary the seed for new grooves.
    --   d1 $ markovGroove 16 42
    let nextState :: String -> Double -> String; nextState st r = if st == fromString "bd" then (if r < 0.6 then "bd" else if r < 0.9 then "sn" else "hh") else if st == fromString "sn" then (if r < 0.4 then "bd" else if r < 0.6 then "sn" else "hh") else (if r < 0.3 then "bd" else if r < 0.5 then "sn" else "hh")
    let markovSeq :: Int -> Int -> [String]; markovSeq n seed = reverse (snd (foldl (\(st, acc) r -> let st' = nextState st r in (st', st' : acc)) (fromString "bd", []) (take n (randomRs (0.0, 1.0) (mkStdGen seed)))))
    let markovGroove n seed = s (fromString (unwords (markovSeq n seed)))

    -- ==== Groove: swing / human timing / accents / fills ==================
    -- (Tidal 1.10 removed `late`/`early`/`groove`; these replace them.)
    -- Swing the whole kit at once:
    let swingKit amt n ps = swingBy amt n (stack ps)
    --   d1 $ swingKit (1/3) 4 [s "bd*4", s "sn(2,8)", s "hh*8"]
    let shuffle = swingBy (1/3) 4
    --   d1 $ shuffle $ s "bd sn hh*4"

    -- Human timing: random micro-offset per event (rand is re-rolled per event)
    let humanize j p = (rand * j) <~ p
    --   d1 $ humanize 0.04 $ s "hh*8"
    let liveHats = humanize 0.05 $ s "hh*8" # gain (0.35 + rand * 0.2)
    let lazySnare = stack [s "bd*4", (0.02 <~) $ s "sn(2,8)"]

    -- Per-step accent ladders (fastFromList, NOT cat — cat spans cycles)
    let ladder gs p = p # gain (fastFromList gs)
    --   d1 $ ladder [0.5,0.5,0.5,0.9,0.5,0.5,0.5,0.9] $ s "hh*8"
    -- Euclidean accents: euclidFull keeps all hits, accents k of them
    let accentEuclid k n amt p = euclidFull k n (p # gain amt) (p # gain 1)
    --   d1 $ accentEuclid 3 8 1.4 (s "bd*8")

    -- Fills / breaks
    let fillEvery n o fill pat = every' n o (const fill) pat
    --   d1 $ fillEvery 4 3 (snareRoll 8) $ s "bd*4 sn(2,8) hh*8"
    let fillTail fill pat = within (0.75, 1) (const fill) pat
    --   d1 $ every 4 (fillTail (s "sn*4" # gain 0.6)) $ s "bd*4 sn(2,8)"
    let snareRoll n = s (fromString (unwords (replicate n "sn"))) # gain (fastFromList [ 0.3 + 0.1 * fromIntegral i | i <- [1..n] ])
    let crashEvery n p = stack [p, every n (const (s "crash" # gain 0.7)) p]
    let maybeFill prob fill pat = sometimesBy prob (const fill) pat
    let breakBar = silence

    -- Density build: 4 → 5 → 6 → 7 → 8 kicks over 5 cycles
    let buildKick = fastcat [ s (fromString (unwords (replicate n "bd"))) | n <- [4,5,6,7,8] ]
    --   d1 $ slow 5 $ buildKick
    let rush n p = stack [p, every n (const (s "sn*8" # gain 0.5)) p]

    -- ==== Fixes to earlier helpers ========================================
    -- Tala with sam/khaali accents: beat 0 loud, vibhag starts louder, pulse soft
    let talaPulse beats = fastFromList [ if i == 0 then 1 else if i `elem` scanl (+) 0 (init beats) then 0.8 else 0.55 | i <- [0 .. sum beats - 1] ]
    --   d1 $ sound "tabla*16" # gain (talaPulse tintal)
    -- Cellular automaton as development: each row = one cycle (not 256 hits)
    let cbit r l c rr = (r `div` (2 ^ (4*l + 2*c + rr))) `mod` 2
    let cstep r xs = [ cbit r (xs !! ((i-1) `mod` length xs)) (xs !! i) (xs !! ((i+1) `mod` length xs)) | i <- [0 .. length xs - 1] ]
    let cell 1 = "bd"
        cell _ = "~"
    let caRows rule n = fastcat (map (s . fromString . unwords . map cell) (take n (iterate (cstep rule) (1 : replicate (n-1) 0))))
    --   d1 $ caRows 110 16

    -- ==== Messiaen: non-retrogradable rhythm + added values ===============
    -- Palindromic durations (symmetric around center).  d1 $ palindur
    let palindur = s "bd ~ bd ~ bd"
    -- Valeur ajoutée: small unit inserted into a regular pattern.
    --   d1 $ addedValue 4     -- bd hh bd hh bd hh bd
    let addedValue n = fastcat (concatMap (\i -> if i < n then [s "bd", s "hh"] else [s "bd"]) [1..n])

    -- ==== Noise melody ====================================================
    -- NOT true 1/f — just a fixed chromatic-ish walk with small steps;
    -- renamed honestly.  d1 $ noiseMel
    let noiseMel = n (fromString "60 63 61 64 62 65 63 60 62 66 64 61") # sound "superpiano" # gain 0.4

    -- ==== Perle cyclic sets ===============================================
    -- Alternating interval cycles (mod 12). (a,b)=(1,6) visits all 12 pitch
    -- classes; (2,3) closes after 9.  d1 $ perle12 1 6
    let perle12 a b = n (fromString (unwords (map show (take 12 (scanl (\x i -> if even i then (x+a) `mod` 12 else (x+b) `mod` 12) 60 [1..]))))) # sound "superhex" # gain 0.3

    -- ==== Hindemith: Series 1/2 ===========================================
    -- Interval consonance rank per Hindemith's Series 1:
    -- P1/P8→P5→P4→M3/м6→м3/M6→M2/м7→м2/M7→тритон (0..7).
    --   d1 $ note (cat [60, 64, 67]) # gain (fromIntegral (7 - hindemithRank 4) / 7)
    let hindemithRank ic = let i = ic `mod` 12 in if i == 0 then 0 else if i == 7 then 1 else if i == 5 then 2 else if i == 4 || i == 8 then 3 else if i == 3 || i == 9 then 4 else if i == 2 || i == 10 then 5 else if i == 1 || i == 11 then 6 else 7
    let hindemithRoot ic = if hindemithRank ic <= 3 then "low" else "high"

    -- ==== Forte: interval vector + prime form ==============================
    --   print (icVector [0,1,4])   -- [1,0,1,1,0,0] for 3-3
    --   print (pcPrime [0,5,8])    -- [0,3,7] (major triad, not [0,5,8])
    let icVector pc = [ length [ (a - b) `mod` 12 | a <- pc, b <- pc, a > b, (a - b) `mod` 12 == ic ] | ic <- [1..6] ]
    let rot xs = [ drop i xs ++ take i xs | i <- [0 .. length xs - 1] ]
    let span12 xs = (last xs - head xs) `mod` 12
    let normalForm xs = let r = foldr1 (\a b -> if span12 a < span12 b then a else if span12 a > span12 b then b else if a < b then a else b) (rot (sort xs)) in map (\x -> (x - head r) `mod` 12) r
    let pcPrime xs = let f = normalForm xs in let g = normalForm (map (\p -> (12 - p) `mod` 12) xs) in if f < g then f else g

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
    -- [articulation, melody, rhythm, texture, writing] binary flags, all 5
    -- used: legato/staccato, melodic contour, tempo, gain, pan.
    --   d1 $ holopova [1,0,1,1,0]
    let holopova ps = fast (if ps !! 2 == 1 then 2 else 1) (note (if ps !! 1 == 1 then cat [60, 62, 64, 65] else cat [67, 64, 62, 60]) # sound "superpiano" # (if ps !! 0 == 1 then legato 0.9 else legato 0.3) # gain (if ps !! 3 == 1 then 0.7 else 0.5) # pan (if ps !! 4 == 1 then 0.3 else 0.7))

    -- ==== Bhatkhande thatas (raga scales) =================================
    -- Only the scales that actually exist in Bhatkhande's 10-thata scheme:
    --   1 Bilawal (major), 5 Kafi, 6 Bhairavi; plus named Bhairav.
    --   d1 $ thatBhairav
    let that 1 = n "60 62 64 65 67 69 71" # sound "superpiano" # gain 0.5   -- Bilawal
        that 5 = n "60 62 63 65 67 69 70" # sound "superpiano" # gain 0.5   -- Kafi
        that 6 = n "60 61 63 64 66 67 69" # sound "superpiano" # gain 0.5   -- Bhairavi
        that _ = n "60 62 64 65 67 69" # sound "superpiano" # gain 0.5
    let thatBhairav = n "60 61 64 65 67 68 70" # sound "superpiano" # gain 0.5   -- C Db E F G Ab B

    -- ==== Maqam ajnas (tetrachords) =======================================
    -- Bayati uses quarter-tones (fractional semitones, 24-TET).
    -- Hijaz is DIATONIC with an augmented second — no quarter-tones:
    --   C Db E F G Ab Bb C (1,3,1,2,1,2,2).
    --   d1 $ maqamBayati   d1 $ maqamHijaz
    let maqamBayati = n "60 61.5 63 64 66 67.5 69 70" # sound "superhex" # gain 0.4
    let maqamHijaz = n "60 61 64 65 67 68 70" # sound "superhex" # gain 0.4

    -- ==== Gamelan slendro / pelog (microtonal tunings) ====================
    --   d1 $ slendro   d1 $ pelog
    let slendro = n "60 62.4 64.8 67.2 69.6" # sound "superhex" # gain 0.4
    -- pelog compressed to one octave (7 tones within 12 semitones)
    let pelog = n "60 61.3 63.4 66.1 67.9 70.8 72" # sound "superhex" # gain 0.4

    -- ==== Xenakis: boolean algebra over pitch sets (Herma) ================
    -- Set ops as pure functions; herma applies one to two pc sets.
    --   d1 $ herma unionSet   d1 $ herma interSet   d1 $ herma diffSet
    let unionSet a b = foldr (\x acc -> if x `elem` acc then acc else x : acc) [] (a ++ b)
    let interSet a b = [ x | x <- a, x `elem` b ]
    let diffSet a b = [ x | x <- a, x `notElem` b ]
    let herma op = n (fromString (unwords (map show (map (+60) (op [0, 1, 4] [0, 3, 7]))))) # sound "superhex" # gain 0.3

    -- ==== Counterpoint ====================================================
    -- NB: this is PARALLEL doubling (organshine), NOT Taneev's invertible
    -- counterpoint — renamed honestly.  d1 $ parallel5 4
    let parallel5 idx = stack [ n "60 62 64 65", n (fromString (unwords (map show (map (+idx) [60, 62, 64, 65])))) ] # sound "superpiano" # gain 0.5
    -- Real invertible counterpoint (Taneev): two voices, then register swap
    --   d1 $ invertible [60, 62, 64, 65] [55, 57, 59, 60]
    let midi xs = n (fromString (unwords (map show xs)))
    let invertible a b = slow 8 $ cat [ stack [midi a, midi b], stack [midi b, midi (map (subtract 12) a)] ] # sound "superpiano"

    -- ==== Harmony: progression / cadence / bass / melody ==================
    -- Chord progression in C minor via mini-notation (i–iv–V7–i).
    --   d1 $ progCminor
    let progCminor = n (cat ["c4'minor", "f4'minor", "g4'dom7", "c4'minor"]) # sound "superpiano" # room 0.5 # size 0.8 # gain 0.6
    -- Authentic cadence V7–I, layered at phrase end.
    --   d2 $ slow 8 $ cadence
    let cadence = n (cat ["g4'dom7", "c4'major"]) # sound "superpiano" # gain 0.7
    -- Bass on progression roots (fixes the missing harmonic foundation).
    --   d1 $ bassCminor
    let bassCminor = n (cat ["c2", "f2", "g2", "c2"]) # sound "bass" # gain 0.8
    -- Melodic arc: up then down (phrase shape), plus a motive with transposition.
    --   d1 $ archMel      d1 $ motPhrase
    let archMel = midi [60, 62, 64, 65, 67, 65, 64, 62] # sound "superpiano" # gain 0.5
    let motPhrase = midi ([60, 64, 67, 64] ++ map (+5) [60, 64, 67, 64] ++ [60]) # sound "superpiano" # gain 0.5

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

    -- 1. Kicks: euclidean groove (3 hits per 8 steps)
    d1 $ euclid 3 8 k

    -- 2. Snare on beats 2 and 4 (real backbeat — NOT euclid 3 8, which
    --    would double the kick; snare slightly late for human feel)
    d2 $ (0.02 <~) $ s "sn(2,8)"

    -- 3. Hi-hats: quarters (euclid 4 8 = every 8th = quarters at 8 steps),
    --    centered pan is default — pan 0.5 would be center, not panned
    d3 $ s "hh(4,8)" # gain 0.5

    -- 4. Random groove generator (re-rolls every cycle!)
    d4 $ randomGroove # gain 0.7

    -- 5. Random euclidean kick (irand re-rolls each cycle)
    d1 $ randomEuclid 8

    -- 6. Bass: simple minor riff
    d5 $ note "c2 d2 e2 g2" # sound "bass" # gain 0.8

    -- 7. Ambient pad on a random minor chord (re-rolls every 4 cycles)
    d6 $ ambientPad

    -- 8. Lead melody: arpeggio
    d7 $ note (arp "up" "c4'maj7") # sound "superpiano" # delay 0.3 # room 0.3

    -- 9. Everything together — swing the whole kit (not just the kick)
    d1 $ swingKit (1/3) 4 [s "bd(3,8)", s "sn(2,8)", s "hh(4,8)"] # gain 0.8

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

    -- 20. Noise melody (fixed chromatic-ish walk)
    d16 $ noiseMel

    -- 21. Harmonic foundation: i–iv–V7–i progression + cadence + bass roots.
    --     (This replaces the perle12 line that used to kill the d7 arpeggio.)
    d7 $ progCminor # gain 0.6
    d8 $ slow 8 $ cadence # gain 0.6
    d9 $ bassCminor # gain 0.8

    -- 22. Hindemith: consonant triad, gain scaled by Series-1 rank
    d8 $ note (cat [60, 64, 67]) # sound "superpiano" # gain (fromIntegral (7 - hindemithRank 4) / 7) # delay 0.3

    -- 23. Messiaen deshi-tala 1 as a tabla accent
    d9 $ talaSound 1 # sound "tabla" # gain 0.5

    -- 24. Yavorsky mode 1 (tritone cell) as a saw melody
    d10 $ yavorsky 1 # gain 0.4

    -- 25. Kholopova parametric complex [articulation=1, melody=0, rhythm=1]
    d11 $ holopova [1, 0, 1, 1, 0] # gain 0.5

    -- 26. Bhatkhande thata 3 (Bhairav) as a scale run
    d12 $ slow 2 $ thatBhairav # gain 0.5

    -- 27. Maqam bayati (quarter-tones via fractional MIDI)
    d13 $ slow 2 $ maqamBayati # gain 0.4

    -- 28. Gamelan slendro (microtonal tuning)
    d14 $ slow 2 $ slendro # gain 0.4

    -- 29. Xenakis Herma: union of two pc sets as a harmony
    d15 $ herma unionSet # gain 0.4

    -- 30. Taneev movable counterpoint at interval 4
    d16 $ invertible [60, 62, 64, 65] [55, 57, 59, 60] # gain 0.5

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
