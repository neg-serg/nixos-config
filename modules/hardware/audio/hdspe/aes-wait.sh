set -u
for _ in $(seq 1 30); do
  if [[ "$(wpctl status 2> /dev/null)" == *"RME AIO Pro"* ]]; then
    exec @pwroute@/bin/pwroute aes
  fi
  sleep 1
done
exit 0
