// Initialize player states
//----------------------------------------------------------------------------
// number of players
3 => int N;
5 => int MAX_BUFFER;

if (me.args()) {
    me.arg(0) => Std.atoi => N;
}

PlayerState ps[N];

class LiSaBuf {
    LiSa lisa;
    time recStart;
    dur recDuration;

    10::second => dur MAX_BUFFER_DURATION;
    1 => int NUM_VOICES;
    20::ms => dur RAMP_TIME;

    MAX_BUFFER_DURATION => lisa.duration;
    NUM_VOICES => lisa.maxVoices;
    RAMP_TIME => lisa.recRamp;

    fun void playLoop() {
        while (true) {
            // <<< "Current recording duration: ", recDuration >>>;
            lisa.getVoice() => int v;
            if (v < 0)
                return;

            lisa.voiceGain(v, .5);
            lisa.rate(v, 1.0);
            lisa.loop(v, 1);

            // <<< "ATTACK" >>>;
            lisa.playPos(v, 0::samp);

            lisa.rampUp(v, RAMP_TIME);
            RAMP_TIME => now;

            // <<< "SUSTAIN" >>>;
            recDuration => now;

            lisa.rampDown(v, RAMP_TIME);
            // <<< "RELEASE" >>>;
            RAMP_TIME => now;
        }
    }
}

class PlayerState {
    // Player ID, 0-indexed
    int ID;
    // Whether the player is ready to catch
    int catchReady;
    // Which ADC channel the player is on
    int adc_channel;
    // Blackhole DAC channel
    int dac_channel;

    // This is a stack of buffers, whatever on the top get recorded or thrown
    LiSaBuf bufs[MAX_BUFFER];
    // pointer to the top buffer
    0 => int p;
    fun PlayerState(int id) { init(id); }

    fun void init(int id) {
        id => ID;
        id => adc_channel;
        id + 8 => dac_channel;

        // The adc & dac channel now won't change, only that some buffers may disconnect / reconnect
        // to the adc & dac channel
        for (int i; i < MAX_BUFFER; i++) {
            adc.chan(adc_channel) => bufs[i].lisa => dac.chan(dac_channel);
            <<< "Player " <= id <= " buffer " <= bufs[i];
        }
    }

    fun LiSaBuf @topBuf() { return bufs[p]; }

    fun void pushBuf(LiSaBuf @buf) {
        (p + 1) % MAX_BUFFER => p;
        buf @=> bufs[p];

        // TODO: maybe should check if they are connected already?
        // connect to the adc & dac
        adc.chan(adc_channel) => bufs[p].lisa => dac.chan(dac_channel);
    }

    fun void popBuf() {
        // disconnect to the adc & dac
        adc =< bufs[p].lisa;
        bufs[p].lisa =< dac.chan(dac_channel);

        (p - 1) % MAX_BUFFER => p;
    }

    fun void playLoop(int id) {
        bufs[id] @=> LiSaBuf buf;
        buf.playLoop();
    }
}

// Initialize N players, ID = i, ADC = i, DAC = i + 8
for (int i; i < N; i++) {
    ps[i].init(i);

    // playLoop always running for all buffers
    for (int j; j < MAX_BUFFER; j++) {
        spork ~ ps[i].playLoop(j);
    }
}

// CLIENT -> SERVER
//----------------------------------------------------------------------------
OscIn oin;
OscMsg msg;

8000 => oin.port;

oin.addAddress("/player/throw");
oin.addAddress("/player/catch");
oin.addAddress("/player/record");

fun void checkThrow(int sourceID, float angle) {
    0 => int throwSuccess;
    int targetID;


    360 / N => float theta;
    ((2 * angle) / theta) - 1 => float targetPOV;
    (sourceID + Math.round(targetPOV + 1) $ int) % N => targetID;

    for (int i; i < N; i++) {
        if (ps[i].ID == targetID && ps[i].catchReady) {
            // ps[i] is the player we are throwing to
            1 => throwSuccess;
        }
    }

    if (throwSuccess) {
        chout <= "player " <= targetID <= " successfuly caught the throw from player " <=
            sourceID <= IO.newline();
        routeAudio(sourceID, targetID);
    }
}

fun void handleRecord(int ID, int toggle) {
    for (int i; i < N; i++) {
        if (ps[i].ID == ID) {
            // the top buffer of that ps
            ps[i].topBuf() @=> LiSaBuf @buf;

            if (toggle) {
                now => buf.recStart;
                buf.lisa.clear();
                buf.lisa.recPos(0::samp);
                chout <= "recording started for player " <= ID <= IO.newline();
                buf.lisa.record(true);
            } else {
                chout <= "recording stopped for player " <= ID <= IO.newline();
                now - buf.recStart => buf.recDuration;
                buf.lisa.record(false);
            }
        }
    }
}

fun void playerListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            chout <= "received message: " <= msg.address <= IO.newline();
            if (msg.address == "/player/throw") {
                if (msg.typetag == "if") {
                    msg.getInt(0) => int ID;
                    msg.getFloat(1) => float angle;
                    chout <= "throw from player: " <= ID <= " at angle " <= angle <= IO.newline();
                    checkThrow(ID, angle);
                }
            }
            if (msg.address == "/player/catch") {
                if (msg.typetag == "ii") {
                    msg.getInt(0) => int ID;
                    msg.getInt(1) => int ready;
                    ready => ps[ID].catchReady;
                    chout <= "catch state: " <= ID <= " " <= ready <= IO.newline();
                }
            }
            if (msg.address == "/player/record") {
                if (msg.typetag == "ii") {
                    msg.getInt(0) => int ID;
                    msg.getInt(1) => int toggle;
                    // TODO: trigger record ON/OFF
                    handleRecord(ID, toggle);
                    chout <= "record state: " <= ID <= " " <= toggle <= IO.newline();
                }
            }
        }
    }
}

spork ~ playerListener();

// SERVER -> CLIENT
//----------------------------------------------------------------------------
// destination port number
// 6449 => int port;

// // array of destination hostnames
// string hostnames[0];

// //----------------------------------------------------------------------------
// // appending names of destinations
// //----------------------------------------------------------------------------

// // hostnames << "localhost";
// // Alex 192.168.180.1
// hostnames << "192.168.176.224"; // Summer
// hostnames << "192.168.186.82";  // Lejun

// // sender object
// OscOut xmit[hostnames.size()];
// // iterate over the OSC transmitters
// for (int i; i < xmit.size(); i++) {
//     // aim the transmitter at destination
//     xmit[i].dest(hostnames[i], port);
// }


fun void routeAudio(int sourceID, int targetID) {
    ps[targetID].pushBuf(ps[sourceID].topBuf());
    ps[sourceID].popBuf();
}


while (true) {
    second => now;
}
