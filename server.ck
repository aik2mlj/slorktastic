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
    200::ms => dur RAMP_TIME;

    MAX_BUFFER_DURATION => lisa.duration;
    NUM_VOICES => lisa.maxVoices;
    RAMP_TIME => lisa.recRamp;

    fun void playLoop() {
        while (true) {
            // <<< "Current recording duration: ", recDuration >>>;
            if (recDuration >= 2 * RAMP_TIME) {
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
                recDuration - 2 * RAMP_TIME => now;

                lisa.rampDown(v, RAMP_TIME);
                // <<< "RELEASE" >>>;
                RAMP_TIME => now;
            } else {
                100::ms => now;
            }
        }
    }
}

class PlayerState {
    // Player ID, 0-indexed
    int ID;
    // Which ADC channel the player is on
    int adc_channel;
    // Blackhole DAC channel
    int dac_channel;

    Dyno lim;
    lim.limit();
    Gain g;

    // effects for continuous control
    Echo echoA[MAX_BUFFER];
    Echo echoB[MAX_BUFFER];
    Echo echoC[MAX_BUFFER];
    PitShift pitchS[MAX_BUFFER];


    // This is a stack of buffers, whatever on the top get recorded or thrown
    LiSaBuf bufs[MAX_BUFFER];
    // pointer to the top buffer
    0 => int p;
    fun PlayerState(int id) { init(id); }

    fun void init(int id) {
        id => ID;
        id => adc_channel;
        id + 8 => dac_channel;
        lim => dac.chan(dac_channel);

        // The adc & dac channel now won't change, only that some buffers may disconnect / reconnect
        // to the adc & dac channel
        for (int i; i < MAX_BUFFER; i++) {
            adc.chan(adc_channel) => bufs[i].lisa => g => echoA[i] => echoB[i] => echoC[i] => pitchS[i] => lim;
            <<< "Player", id, "buffer", bufs[i] >>>;
        }
    }

    fun LiSaBuf @topBuf() { return bufs[p]; }

    fun LiSaBuf @pushBuf(LiSaBuf @buf) {
        // push the buf to the top, and pop the old bottom and return its reference
        (p + 1) % MAX_BUFFER => p;

        bufs[p] @=> LiSaBuf @oldBuf;
        adc =< oldBuf.lisa;
        oldBuf.lisa =< g;

        buf @=> bufs[p];

        // TODO: maybe should check if they are connected already?
        // connect to the adc & dac
        adc.chan(adc_channel) => bufs[p].lisa => g;

        return oldBuf;
    }

    fun void popBuf(LiSaBuf @vacantBuf) {
        // disconnect to the adc & dac
        adc =< bufs[p].lisa;
        bufs[p].lisa =< g;

        // clear the vacantBuf
        vacantBuf.lisa.clear();
        vacantBuf.lisa.recPos(0::samp);

        vacantBuf @=> bufs[p];

        // connect the vacantBuf to the adc & dac
        adc.chan(adc_channel) => bufs[p].lisa => g;

        (p - 1) % MAX_BUFFER => p;
    }

    fun void popSelf() {
        // this is different from popBuf that we don't need to disconnect the pipeline
        // just clear the lisa buffer and rotate the pointer
        bufs[p].lisa.clear();
        bufs[p].lisa.recPos(0::samp);

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
oin.addAddress("/player/steal");
oin.addAddress("/player/record");
oin.addAddress("/player/xyz_pos");
oin.addAddress("/player/pop");

fun void doThrow(int sourceID, float angle) {
    int targetID;

    360 / N => float theta;
    ((2 * angle) / theta) - 1 => float targetPOV;
    (sourceID + Math.round(targetPOV + 1) $ int) % N => targetID;

    if (targetID != sourceID) {
        chout <= "player " <= sourceID <= " threw to player " <= targetID <= IO.newline();
        routeAudio(sourceID, targetID);
    }
}

fun void doSteal(int sourceID, float angle) {
    int targetID;

    (angle + 180) % 360 => float targetAngle;

    360 / N => float theta;
    ((2 * targetAngle) / theta) - 1 => float targetPOV;
    (sourceID + Math.round(targetPOV + 1) $ int) % N => targetID;

    if (targetID != sourceID) {
        chout <= "player " <= sourceID <= " stole from player " <= targetID <= IO.newline();
        routeAudio(targetID, sourceID);
    }
}

fun void continuousControlListener(int ID, float x_pos, float y_pos, float z_pos) {
    for (int i; i < N; i++) {
        if (ps[i].ID == ID) {

            // Pitch shifting
            ps[i].pitchS[i].mix(x_pos);
            ps[i].pitchS[i].shift(z_pos);

            // Echo
            ps[i].echoA[i].mix(.5);
            ps[i].echoB[i].mix(.5);
            ps[i].echoC[i].mix(.5);
            x_pos::second => dur x_dur;
            y_pos::second => dur y_dur;
            z_pos::second => dur z_dur;
            ps[i].echoA[i].delay(x_dur);
            ps[i].echoB[i].delay(y_dur);
            ps[i].echoC[i].delay(z_dur);
        }
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

fun void handlePop(int ID) {
    for (int i; i < N; i++) {
        if (ps[i].ID == ID) {
            ps[i].popSelf();
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
                    chout <= "throw attempt by player: " <= ID <= " with angle " <= angle <=
                        IO.newline();
                    doThrow(ID, angle);
                }
            }
            if (msg.address == "/player/steal") {
                if (msg.typetag == "if") {
                    msg.getInt(0) => int ID;
                    msg.getFloat(1) => float angle;
                    chout <= "steal attempt by player: " <= ID <= " with angle " <= angle <=
                        IO.newline();
                    doSteal(ID, angle);
                }
            }
            if (msg.address == "/player/record") {
                if (msg.typetag == "ii") {
                    msg.getInt(0) => int ID;
                    msg.getInt(1) => int toggle;
                    // TODO: trigger record ON/OFF
                    handleRecord(ID, toggle);
                    string recordState;
                    if (toggle)
                        "ON" => recordState;
                    else
                        "OFF" => recordState;
                    chout <= "player " <= ID <= " recording state: " <= recordState <= IO.newline();
                }
            }
            if (msg.address == "/player/pop") {
                if (msg.typetag == "i") {
                    msg.getInt(0) => int ID;
                    handlePop(ID);
                    chout <= "player " <= ID <= " popped buf" <= IO.newline();
                }
            }

            if (msg.address == "/player/xyz_pos") {
                if (msg.typetag == "ifff") {
                    msg.getInt(0) => int ID;
                    msg.getFloat(1) => float x_pos;
                    msg.getFloat(2) => float y_pos;
                    msg.getFloat(3) => float z_pos;
                    continuousControlListener(ID, x_pos, y_pos, z_pos);
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
    ps[targetID].pushBuf(ps[sourceID].topBuf()) @=> LiSaBuf @oldBuf;
    ps[sourceID].popBuf(oldBuf);
}


while (true) {
    second => now;
}
