// virtual-midi — create N virtual ALSA sequencer ports and hold them open.
// User-space equivalent of snd-virmidi: gives SuperCollider stable MIDI
// destinations for the synth routing slots (no hardware, no loops).
#include <alsa/asoundlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 4;
    snd_seq_t *seq = NULL;
    if (snd_seq_open(&seq, "default", SND_SEQ_OPEN_DUPLEX, 0) < 0) {
        fprintf(stderr, "virtual-midi: snd_seq_open failed\n");
        return 1;
    }
    snd_seq_set_client_name(seq, "virtual-midi");
    for (int i = 0; i < n; i++) {
        char name[32];
        snprintf(name, sizeof name, "out%d", i);
        int port = snd_seq_create_simple_port(
            seq, name,
            SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_WRITE |
                SND_SEQ_PORT_CAP_SUBS_READ | SND_SEQ_PORT_CAP_SUBS_WRITE,
            SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
        if (port < 0) {
            fprintf(stderr, "virtual-midi: port %s failed\n", name);
            break;
        }
        fprintf(stderr, "virtual-midi: port %s (%d)\n", name, port);
    }
    for (;;) pause();
    return 0;
}
