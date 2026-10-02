# Quiet fan profile data for hosts/odin/services/policy.nix: the CPU and GPU
# curves the nct6775/amdgpu fancontrol units are generated from.
{
  autoFancontrol = {
    enable = true;
    # Aggressive silence at idle, ramp up quickly under load
    minTemp = 62; # °C — stay quiet until significant heat
    maxTemp = 75; # °C — reach full speed before hitting thermal limit
    minPwm = 64; # ~25% (was 15), absolute minimum (fans may stall)
    maxPwm = 178; # capped at 70% to reduce noise under load
    hysteresis = 5; # reduce fan speed oscillation
    interval = 2; # responsive polling
    allowStop = false; # fans never fully stop for safety
    minStartOverride = 150; # reliable spin-up from low PWM
    gpuPwmChannels = [ ]; # case fans follow CPU temperature
  };

  gpuFancontrol = {
    enable = true;
    # GPU fan stays silent at idle, ramps for load
    minTemp = 62; # °C — GPU fan quiet until significant heat
    maxTemp = 75; # °C — full speed well before throttle point
    minPwm = 15; # ~25% (was 15), absolute minimum
    maxPwm = 178; # capped at 70% for improved acoustics
    hysteresis = 5; # stability
  };
}
