# AMT: Piano audio-to-MIDI - obzor 2018-2026 (open-weight)

## 1. Tablitsa modelei

Uslovnye oboznacheniya:

- [OK] = chislo podtverzhdeno snipetami istochnikov v etoy sessii
- [T] = chislo shiroko tsitiruetsya, no tochnuyu tablitsu vytyan nut ne udalos; proverit
- "ne naydeno" = v dostupnyh snipetah ne nashlos

| Model                                              | Paper / god                            | Open weights (URL)                                                                                         | Arhitektura                                                                                   | Parametry                           | Tochnost (MAESTRO)                                                                                                                          | Dannye                                                       | Litsenziya                                  | Runtime                           | Prim.                                                                                                                               |
| -------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| basic-pitch (Spotify)                              | ICASSP 2022, arXiv 2203.09893          | github.com/spotify/basic-pitch (ONNX v relizah); HF spotify/basic-pitch                                    | Harmonic-stacking CNN, very shallow                                                           | ~16.8K (emergentmind), ONNX ~230 KB | note F1 0.895[T] (MAESTRO v3, tablitsa statyi)                                                                                              | MAESTRO + GuitarSet + sintetich. MIDI                        | [OK] Apache-2.0                             | ONNX, CPU real-time               | nashe tekushchee baseline                                                                                                           |
| Onsets & Frames (Magenta)                          | ICML 2018, arXiv 1710.11153            | magenta/magenta models/onsets_frames_transcription (GCS chekpointy); port DBraun/onsets-and-frames         | CNN+LSTM, frame+onset heads                                                                   | ne naydeno                          | onset F1 [OK] 94.80% (Kong 2010.01815 + sota2); note F1 ne naydeno                                                                          | MAESTRO v1                                                   | [OK] Apache-2.0                             | TF, GPU/CPU                       | istoricheski vazhna                                                                                                                 |
| ByteDance high-res (piano_transcription_inference) | ISMIR 2020, arXiv 2010.01815           | github.com/bytedance/piano_transcription; pip piano-transcription-inference; HF Genius-Society/piano_trans | CNN+biGRU, regressiya onset/offset + pedal                                                    | ne naydeno                          | onset F1 [OK] 96.72% (abstract 2010.01815; vosp. 96.7 v 2402.01424); pedal onset 91.86%                                                     | GiantMIDI-Piano + MAESTRO                                    | [WARN] ne podtverzhdeno (na HF "other=art") | PyTorch, CPU/GPU                  | velocity + pedal; standart 2020-2022                                                                                                |
| MT3 (Google)                                       | ICLR 2022, arXiv 2110.07417            | github.com/magenta/mt3; TF Hub magenta/mt3; port HF m-a-p/MT3                                              | T5-style seq2seq Transformer, mel -> MIDI tokens                                              | ~220-300M (T5-base)                 | note F1 0.973[T] (MAESTRO v3, tablitsa statyi)                                                                                              | 6 datasetov (MAESTRO, MusicNet, GuitarSet, URMP, Slakh, DW5) | [OK] Apache-2.0                             | JAX/TF, GPU bystree, CPU medlenno | multitrack; bez velocity                                                                                                            |
| hFT-Transformer (Sony)                             | ISMIR 2023, arXiv 2307.04305           | github.com/sony/hFT-Transformer (vesa: "download and put under checkpoint/MAESTRO")                        | 2-urovnevyi Transformer (chastotnyi + vremennoi), regressiya onset/offset                     | 5.5M (sota2)                        | note F1 [OK] 95.44, onset 97.44 (sota2 + sotaverified); MIREX 2024: 0.9416 / holistic 0.8359                                                | MAESTRO                                                      | [OK] MIT (Sony 2023)                        | PyTorch, CPU ok (medlenno)        | piano-only SOTA 2023                                                                                                                |
| Transkun (U.Rochester)                             | ISMIR 2024, arXiv 2404.09466           | github.com/Yujia-Yan/TransKun; pip transkun (chekpoint v pakete)                                           | encoder-only Transformer + neural semi-CRF                                                    | 12.9M (sota2)                       | note F1 [OK] 97.16, onset 98.32 (sota2); 93.48 note w/offset = SOTA na MAESTRO v3 leaderboard; MIREX V2 0.9490/0.8764, V2-Aug 0.9648/0.9081 | MAESTRO                                                      | [WARN] ne podtverzhdeno                     | PyTorch, CPU ok                   | default chekpoint bez pedali; prost v ustanovke                                                                                     |
| SFT-CRNN                                           | 2025 (sota2, 2026.05); paper ne nayden | ne naydeno                                                                                                 | CRNN (sparse freq-time)                                                                       | 15M (sota2)                         | note F1 [OK] 97.46, onset 98.36 (claimed, sota2)                                                                                            | ne naydeno                                                   | ne naydeno                                  | ne naydeno                        | verifitsirovat                                                                                                                      |
| HPPNet                                             | ISMIR 2022, arXiv 2208.14339           | github.com/WX-Wei/HPPNet                                                                                   | Harmonic Dilated Conv + Frequency Grouped RNN                                                 | HPPNet-sp 1.2M (sota2)              | stroka na sota2 obrezana snipetom (98.45...), polnoe znachenie ne naydeno                                                                   | MAESTRO                                                      | ne podtverzhdeno                            | PyTorch, GPU/CPU                  | kompaktnaya                                                                                                                         |
| D3RM                                               | ICASSP 2025, arXiv 2501.05068          | github.com/hanshounsu/d3rm (README: Model Download)                                                        | Neighborhood Attention denoising decoder + pretrained acoustic encoder (diffusion refinement) | ne naydeno                          | note F1 [OK] 97.57, s offsetami 90.44 (pith.science); baseline FF 96.45/87.60                                                               | MAESTRO                                                      | ne podtverzhdeno                            | PyTorch + natten (GPU proshche)   | tyazhelyi inference (iterativnyi diffusion)                                                                                         |
| YourMT3+                                           | 2025                                   | github.com/mimbres/YourMT3; vesa HF mimbres/YourMT3                                                        | MT3-podobnyi T5 (MoE varianty)                                                                | ne naydeno                          | onset F1 [OK] 96.98 (YPTF.MoE+M noPS, sotaverified); note F1 ne naydeno                                                                     | mnogoinstrumentalnye + stem augmentation                     | ne podtverzhdeno                            | PyTorch/JAX port                  | multitrack                                                                                                                          |
| MuScriptor (Kyutai+Mirelo)                         | arXiv 2607.08168 (2026)                | HF MuScriptor/muscriptor-large (gated); github.com/muscriptor/muscriptor                                   | decoder-only Transformer, mel-conditioning, MT3-stil tokeny                                   | 60M (large)                         | MAESTRO piano F1 ne naydeno; svoy bench F1 47.7 (mix)                                                                                       | realnye mnogodorozhechnye zapisi                             | [WARN] CC BY-NC 4.0 (non-commercial, gated) | GPU/CPU                           | tselye miksy; bez velocity                                                                                                          |
| Omnizart                                           | JOSS 2021                              | github.com/Music-and-Culture-Technology-Lab/omnizart                                                       | 3 modeli: music (pianoroll), drum, chord                                                      | ne naydeno                          | MAESTRO F1 ne naydeno                                                                                                                       | GiantMIDI-Piano, Slakh i dr.                                 | ne podtverzhdeno (JOSS, open source)        | PyTorch, GPU/CPU                  | universalnyi toolkit                                                                                                                |
| GiantMIDI-Piano                                    | TISMIR 2021, arXiv 2010.07061          | github.com/bytedance/GiantMIDI-Piano (dataset)                                                             | - (dataset, transkribirovan modele Kong)                                                      | -                                   | -                                                                                                                                           | -                                                            | -                                           | -                                 | ne model; istochnik dannyh                                                                                                          |
| Remi                                               | Pop Music Transformer, 2020            | -                                                                                                          | -                                                                                             | -                                   | -                                                                                                                                           | -                                                            | -                                           | -                                 | NE AMT: simvolicheskaya tokenizatsiya MIDI dlya generatsii (miditok docs)                                                           |
| KaraTuner                                          | 2024 (ByteDance)                       | -                                                                                                          | -                                                                                             | -                                   | -                                                                                                                                           | -                                                            | -                                           | -                                 | NE AMT: eto pitch correction dlya vokala (karaoke). Edinstvennyi KaraTuner v literature - imenno on. Kandidat iz zadaniya - oshibka |

## 2. Top-5 po tochnosti (note F1, MAESTRO; mettiki razlichayutsya)

1. D3RM - 97.57 note F1 / 90.44 s offset (ICASSP 2025); vesa v repo; inference dorogoi
1. SFT-CRNN - 97.46 / onset 98.36 (claimed, sota2); kod/vesa NE naideny
1. Transkun - 97.16 / onset 98.32; 93.48 note F1 (w/ offset) = SOTA MAESTRO v3 leaderboard; pip
   install transkun
1. MT3 - 0.973[T] note F1 (iz statyi); multitrack, Apache-2.0
1. hFT-Transformer - 95.44 / onset 97.44 (claimed) + MIREX holistic 0.8359; MIT, vesa v repo

Prakticheski dlya piano-only: Transkun (prostota + tochnost + CPU) ili hFT-Transformer. D3RM - esli
nuzhen maksimum i est GPU/terpenie.

## 3. Vazhnye ogovorki

- Metriki nesravnimy mezhdu kolonkami: "note F1", "note w/ offset", "holistic (s velocity)",
  MIREX-average - raznye protokoly (mir_eval tolerance). Sravnivat tolko vnutri odnogo istochnika.
- MAESTRO - laboratorno-sinteticheskii bench (Disklavier); na realnyh zapisyah tochnost padaet:
  2402.01424 (augmentations), MulTTiPop ~38% onset F1 u luchshei modeli.
- paperswithcode zakryt (Meta, iyul 2025); zerkala: sota2.com i sotaverified.org (chisla pomecheny
  "claimed").
- 2025 AMT Challenge (arXiv 2603.27528): 8 komand, 2 oboshli baseline MT3.
- Neproverennye litsenzii (bytedance, Transkun, D3RM, HPPNet, YourMT3+) pomecheny WARN - proverit
  LICENSE v repozitoriyah. MuScriptor - garantirovanno non-commercial (CC BY-NC 4.0, gated).
- Zakrytye produkty (Melodyne i t.p.) ne vklyucheny, kak prosili.

## 4. Klyuchevye istochniki (URL)

- basic-pitch: arxiv.org/abs/2203.09893; github.com/spotify/basic-pitch;
  huggingface.co/spotify/basic-pitch; LICENSE
  github.com/victoria-mckinney/basic-pitch/blob/main/LICENSE
- Onsets & Frames: arxiv.org/abs/1710.11153; github.com/magenta/magenta
  (models/onsets_frames_transcription); onset 94.80%: arxiv.org/abs/2010.01815;
  sota2.com/research/sota/piano-transcription-on-maestro-test
- Kong/ByteDance: arxiv.org/abs/2010.01815; github.com/bytedance/piano_transcription;
  pypi.org/project/piano-transcription-inference; 96.72% onset: arxiv.org/abs/2010.01815; vosp.
  96.7: arxiv.org/html/2402.01424v1
- MT3: arxiv.org/abs/2110.07417; github.com/magenta/mt3; tfhub.dev/google/magenta/mt3/1; LICENSE
  github.com/magenta/mt3/blob/main/LICENSE; port huggingface.co/m-a-p/MT3
- hFT-Transformer: arxiv.org/abs/2307.04305; github.com/sony/hFT-Transformer; LICENSE
  github.com/sony/hFT-Transformer/blob/master/LICENSE (MIT);
  sota2.com/research/sota/music-transcription-on-maestro;
  sotaverified.org/tasks/music-transcription;
  music-ir.org/mirex/wiki/2024:Polyphonic_Transcription_Results
- Transkun: arxiv.org/abs/2404.09466; github.com/Yujia-Yan/TransKun; pypi.org/project/transkun;
  sota2.com/research/sota/automatic-piano-transcription-on-maestro-v3-0-0-test
- D3RM: arxiv.org/abs/2501.05068; github.com/hanshounsu/d3rm; 97.57/90.44:
  pith.science/paper/2501.05068
- YourMT3+: huggingface.co/mimbres/YourMT3; github.com/mimbres/YourMT3; onset 96.98:
  sotaverified.org/tasks/music-transcription
- HPPNet: arxiv.org/abs/2208.14339; github.com/WX-Wei/HPPNet
- MuScriptor: huggingface.co/MuScriptor/muscriptor-large; github.com/muscriptor/muscriptor;
  arxiv.org/abs/2607.08168 (CC BY-NC 4.0)
- Omnizart: github.com/Music-and-Culture-Technology-Lab/omnizart
- GiantMIDI-Piano: arxiv.org/abs/2010.07061; github.com/bytedance/GiantMIDI-Piano
- REMI (ne AMT): miditok.readthedocs.io/en/v3.0.2/tokenizations.html
- KaraTuner (ne AMT, pitch correction): arXiv "KaraTuner: Towards End-to-End Natural Pitch
  Correction for Singing Voice in Karaoke"
- 2025 AMT Challenge: arxiv.org/abs/2603.27528
- Realnye benchi: MulTTiPop alanhou.org/blog/arxiv-multtipop-a-multitrack-transcription-dataset-for;
  2402.01424 arxiv.org/abs/2402.01424
