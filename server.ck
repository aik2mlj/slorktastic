// Initialize player states
//----------------------------------------------------------------------------
// number of players
3 => int N;

if (me.args()) {
    me.arg(0) => Std.atoi => N;
}

PlayerState ps[N];

class PlayerState {
    // Player ID, 0-indexed
    int ID;
    // Whether the player is ready to catch
    int catchReady;
    // Which ADC channel the player is on
    int adc_channel;
    // Blackhole DAC channel
    int dac_channel;
    // The dac channel that the player has thrown to
    int target_channel;

    LiSa buf;
    now => time recStart;
    dur recDuration;

    10::second => dur MAX_BUFFER_DURATION;
    8 => int NUM_VOICES;
    20::ms => dur RAMP_TIME;

    MAX_BUFFER_DURATION => buf.duration;
    NUM_VOICES => buf.maxVoices;
    RAMP_TIME => buf.recRamp;

    fun PlayerState(int id) { init(id); }

    fun void init(int id) {
        id => ID;
        id => adc_channel;
        id + 8 => dac_channel;
        dac_channel => target_channel;

        adc.chan(adc_channel) => dac.chan(dac_channel);
    }

    fun void playLoop() {
        while (true) {
            buf.getVoice() => int v;
            if (v < 0)
                return;

            buf.voiceGain(v, .5);
            buf.rate(v, 1.0);
            buf.loop(v, 1);

            <<< "ATTACK" >>>;
            buf.playPos(v, 0::samp);

            buf.rampUp(v, RAMP_TIME);
            RAMP_TIME => now;

            <<< "SUSTAIN" >>>;
            recDuration - 2 * RAMP_TIME => now;

            buf.rampDown(v, RAMP_TIME);
            <<< "RELEASE" >>>;
            RAMP_TIME => now;
        }
    }
}

// Initialize N players, ID = i, ADC = i, DAC = i + 8
for (int i; i < N; i++) {
    ps[i].init(i);
    spork ~ ps[i].playLoop();
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
    -999 => int sourceChan;
    -999 => int targetChan;
    int oldTargetChan;
    int targetID;


    360 / N => float theta;
    ((2 * angle) / theta) - 1 => float targetPOV;
    (sourceID + Math.round(targetPOV + 1) $ int) % N => targetID;

    for (int i; i < N; i++) {
        if (ps[i].ID == sourceID) {
            ps[i].adc_channel => sourceChan;
            ps[i].target_channel => oldTargetChan;
        }

        if (ps[i].ID == targetID && ps[i].catchReady) {
            // ps[i] is the player we are throwing to
            ps[i].dac_channel => targetChan;
        }
    }

    if (sourceChan != -999 && targetChan != -999) {
        chout <= "player " <= targetID <= " successfuly caught the throw from player " <=
            sourceID <= IO.newline();
        routeAudio(sourceChan, targetChan, oldTargetChan);
    }
}

fun void handleRecord(int ID, int toggle) {
    for (int i; i < N; i++) {
        if (ps[i].ID == ID) {
            if (toggle) {
                now => ps[i].recStart;
                chout <= "recording started for player " <= ID <= IO.newline();
                ps[i].buf.record(true);
            } else {
                chout <= "recording stopped for player " <= ID <= IO.newline();
                now - ps[i].recStart => ps[i].recDuration;
                ps[i].buf.record(false);
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


fun void routeAudio(int source, int target, int oldTarget) {
    chout <= "routing audio from ADC channel " <= source <= " to DAC channel " <= target <=
        IO.newline();
    adc.chan(source) =< dac.chan(oldTarget);
    adc.chan(source) => dac.chan(target);
}


while (true) {
    second => now;
}
