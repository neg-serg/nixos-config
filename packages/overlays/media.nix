inputs: final: prev:
let
  # Name-based package lookup: `pkg "swayimg"` is packages/swayimg/default.nix
  # (neg.functions.pkg walks the tree), so no call site counts `../` levels.
  functions = final.neg.functions;
  call = functions.callPkg;
  pkg = functions.pkg;
in
{
  pwroute = call (inputs.rust-pkgs + "/pwroute/package.nix") { };
  # MPD client for large libraries: Node backend + React UI, served on loopback.
  # CamillaDSP's browser equalizer (Svelte client + Fastify server): the upstream
  # reference UI on loopback; the headphone catalogue serves aurora's own /eq page.
  # ggml-based runtime for local audio models (prebuilt Vulkan build); it runs
  # Audio Flamingo Next GGUF on the GPU when the ROCm torch path cannot.
  # Kernel module (RME HDSPe ALSA driver) — takes `kernel`; the default kernel
  # set is a placeholder, the host overrides it with the actual boot kernel.
  snd-hdspe = call (pkg "snd-hdspe") { kernel = prev.linuxPackages.kernel; };
  # Python libs for the CamillaGUI backend (camilladsp / camilladsp_plot modules)
  # CamillaDSP itself, built with the native PipeWire backend (`pipewire-backend`):
  # the insert is two filter nodes in the graph instead of the ALSA `pipewire`
  # PCM plugin, which hands out reads of the graph quantum and cannot take a
  # bigger chunksize without a warning per read.
  #
  # The patch below belongs to the ALSA backend: with the PipeWire ALSA plugin as
  # its capture device the PCM fd stays readable while no frames are there, so
  # `readi` answers EAGAIN and the backend retries without yielding — a whole
  # core, measured 2026-11-04 (1.29M retries in three seconds). It stays for
  # configs that still use that path.
  camilladsp = prev.camilladsp.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ prev.pipewire ];
    cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [ "pipewire-backend" ];
    patches = (old.patches or [ ]) ++ [ ./camilladsp-eagain-wait.patch ];
  });
  # VapourSynth NCNN (Vulkan) plugin: AI upscale/interp/denoise in VS (GPL-3)
  vsncnn = call (pkg "vsncnn") { };
  # -- metering / delivery --
  # Prebuilt upstream bundles: the Flutter meter canvas (with the VST3 that
  # feeds it from a DAW) and `oaa`, the same engine for one file at a time.
  oaa = call (pkg "oaa-cli") { }; # oaa master.wav --target streaming-14 -> exit code
}
