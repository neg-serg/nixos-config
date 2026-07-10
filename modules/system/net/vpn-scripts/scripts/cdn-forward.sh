socat TCP-LISTEN:10808,fork,bind=192.168.122.1,reuseaddr TCP:127.0.0.1:10808 &
python3 /tmp/cdn-ondemand.py &
