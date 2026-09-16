local P = require('luasnip_pre')
local ls, s, i, t, c, fmt = P.ls, P.s, P.i, P.t, P.c, P.fmt

-- SuperCollider live-coding snippets (raw SC / scnvim session).
-- Trigger with <C-j> (expand) after typing the trig word.
ls.add_snippets("supercollider", {
  -- SynthDef: sdef<CR>
  s('sdef', fmt([[
    SynthDef(\{name}, {{ |out = 2, freq = 440, amp = 0.2, sustain = 1, pan = 0|
      var env = EnvGen.kr(Env.perc(0.01, sustain), doneAction: 2);
      var sig = SinOsc.ar(freq) * env * amp;
      Out.ar(out, Pan2.ar(sig, pan));
    }}).add;
    {body}
  ]], {
    name = i(1, 'mySynth'),
    body = i(0),
  })),

  -- Ndef pattern: ndef<CR>
  s('ndef', fmt([[
    Ndef(\{name}, {{ |freq = 220, amp = 0.15|
      var sig = SinOsc.ar([freq, freq * 1.01], 0, 0.5).sum;
      sig = RLPF.ar(sig, LFNoise1.kr(0.1).range(300, 1500), 0.5);
      sig * amp
    }}).play;
    {body}
  ]], {
    name = i(1, 'pad'),
    body = i(0),
  })),

  -- Pdef + Pbind: pdef<CR>
  s('pdef', fmt([[
    Pdef(\{name}, Pbind(
      \instrument, \{instr},
      \degree, Pseq({degs}, inf),
      \dur, {dur},
      \amp, {amp},
      \legato, 0.8
    )).play;
    {body}
  ]], {
    name = i(1, 'seq'),
    instr = i(2, 'sine'),
    degs = i(3, '[0, 3, 5, 7, 10, 7, 5, 3]'),
    dur = i(4, '0.25'),
    amp = i(5, '0.15'),
    body = i(0),
  })),

  -- Pbind inline on a bus: pbin<CR>
  s('pbin', fmt([[
    Pbind(
      \instrument, \{instr},
      \note, Pseq({notes}, inf),
      \dur, {dur},
      \amp, {amp},
      \out, {out}
    ).play;
    {body}
  ]], {
    instr = i(1, 'dshPiano162'),
    notes = i(2, '[60, 64, 67, 72]'),
    dur = i(3, '0.5'),
    amp = i(4, '0.8'),
    out = i(5, '2'),
    body = i(0),
  })),

  -- Hush all: hush<CR>
  s('hush', t([[
    s.freeAll; Ndef.clear; Pdef.all.do(_.stop);
  ]])),

  -- Boot server: boot<CR>
  s('boot', t([[
    s.options.numOutputBusChannels = 2;
    s.options.numBuffers = 8192;
    s.options.memSize = 1024 * 1024;
    s.boot;
  ]])),
})
