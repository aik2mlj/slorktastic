@import "PlinkyRev"
@import "quantize.ck"

// Initialize player states
//----------------------------------------------------------------------------
// number of players
3 => int N;
5 => int MAX_BUFFER;

if (me.args()) {
    me.arg(0) => Std.atoi => N;
}

["audio/monologue1_verb.wav", "audio/monologue2_verb.wav", "audio/monologue3_verb.wav"] @=> string monologuePath[];

PlayerState ps[N];
QuantizeStatus qtStatus;
spork ~ qtStatus.playKickLoop();

class LiSaBuf {
    LiSa lisa;
    time recStart;
    dur recDuration;
    float durationScalingFactor;
    1.0 => float playbackRate;
    dur qtDuration;

    .25 => float MAX_GAIN_BASE;
    .25 => float MAX_GAIN;

    10::second => dur MAX_BUFFER_DURATION;
    1 => int NUM_VOICES;
    200::ms => dur RAMP_TIME;

    MAX_BUFFER_DURATION => lisa.duration;
    NUM_VOICES => lisa.maxVoices;
    RAMP_TIME => lisa.recRamp;

    // WARNING: we are using the global qtStatus, might not be the best
    fun void setQuantize() { qtStatus.getQuantizedDur(recDuration) => qtDuration; }

    fun void playLoop() {
        while (true) {
            // determine using quantized or original recorded duration
            // WARNING: we are using the global qtStatus, might not be the best
            // <<< "quantize:", qtStatus.on >>>;
            // now quantization always on, pressing q just enable the kick
            qtDuration => dur d;
            // if (qtStatus.on)
            //     qtDuration => d;
            // else
            //     recDuration => d;

            if (d >= 2 * RAMP_TIME) {
                lisa.getVoice() => int v;
                if (v < 0)
                    return;

                lisa.voiceGain(v, MAX_GAIN);
                lisa.rate(v, playbackRate);
                // lisa.loop(v, 1);

                // <<< "ATTACK" >>>;
                lisa.playPos(v, 0::samp);

                lisa.rampUp(v, RAMP_TIME);
                RAMP_TIME => now;

                // <<< "SUSTAIN" >>>;
                d - 2 * RAMP_TIME => now;

                lisa.rampDown(v, RAMP_TIME);
                // <<< "RELEASE" >>>;
                RAMP_TIME => now;
            } else {
                100::ms => now;
            }
        }
    }

    fun void fadeOut() {
        for (int i; i < 50; i++) {
            lisa.voiceGain(0, MAX_GAIN * (1 - i / 100.0));
            1::ms => now;
        }
    }

    fun void fadeIn() {
        for (int i; i < 50; i++) {
            lisa.voiceGain(0, MAX_GAIN * i / 100.0);
            1::ms => now;
        }
    }

    fun void clear() {
        lisa.clear();
        lisa.recPos(0::samp);
        100::second => recDuration;
    }
}

class PlayerState {
    // Player ID, 0-indexed
    int ID;
    // Which ADC channel the player is on
    int adc_channel;
    // Blackhole DAC channel
    int dac_channel;

    // whether the player is recording (bool)
    false => int RECORDING;

    0 => int mode; // 0: loop + throw, 1: modulate monologue

    Dyno lim_postFX;
    lim_postFX.slopeBelow(1.0);
    lim_postFX.slopeAbove(.01);
    lim_postFX.thresh(.4);
    lim_postFX.attackTime(10::ms);
    lim_postFX.releaseTime(200::ms);
    Dyno lim_preFx;
    lim_preFx.slopeBelow(1.0);
    lim_preFx.slopeAbove(.01);
    lim_preFx.thresh(.5);
    lim_preFx.attackTime(10::ms);
    lim_preFx.releaseTime(200::ms);
    Gain preFX;

    // effects for continuous control
    Echo echoA[MAX_BUFFER];
    Echo echoB[MAX_BUFFER];
    Echo echoC[MAX_BUFFER];
    PitShift pitchS[MAX_BUFFER];
    DelayL delayL[MAX_BUFFER];
    Gain postFX;
    postFX.gain(1.0);

    PlinkyRev pRev[MAX_BUFFER];
    for (int i; i < MAX_BUFFER; i++) {
        pRev[i].mix(0.5);
    }

    SndBuf monologueBuf[N] => Chorus chorus[N];

    // This is a stack of buffers, whatever on the top get recorded or thrown
    LiSaBuf bufs[MAX_BUFFER];
    // pointer to the top buffer
    0 => int p;
    fun PlayerState(int id) { init(id); }

    fun void init(int id) {
        id => ID;
        id => adc_channel;
        id + 8 => dac_channel;
        lim_postFX => dac.chan(dac_channel);

        // The adc & dac channel now won't change, only that some buffers may disconnect / reconnect
        // to the adc & dac channel
        postFX => lim_postFX;
        for (int i; i < MAX_BUFFER; i++) {
            adc.chan(adc_channel) => bufs[i].lisa => preFX => lim_preFx => pitchS[i] => pRev[i] => postFX;
            // adc.chan(adc_channel) => bufs[i].lisa => postFX;
            // delayL[i].gain(.99);
            // 4000::ms => delayL[i].max => delayL[i].delay;
            // .5 => pitchS[i].mix => echoA[i].mix => echoB[i].mix => echoC[i].mix;
            // 4000::ms => echoA[i].max => echoB[i].max => echoC[i].max;
            <<< "Player", id, "buffer", bufs[i] >>>;
        }

        for(int i; i < N; i++) {
            chorus[i] => dac.chan(dac_channel);
            chorus[i].mix(0);
            chorus[i].modDepth(0);
            chorus[i].modFreq(50);

            monologuePath[i] => monologueBuf[i].read;
            if (!monologueBuf[i].ready())
                <<< "failed to load monologue file", monologuePath[i] >>>;
            else
                <<< "monologue file loaded", monologuePath[i] >>>;
            monologueBuf[i].gain(0);
        }
    }

    fun LiSaBuf @topBuf() { return bufs[p]; }

    fun LiSaBuf @pushBuf(LiSaBuf @buf) {
        // push the buf to the top, and pop the old bottom and return its reference
        (p + 1) % MAX_BUFFER => p;

        bufs[p] @=> LiSaBuf @oldBuf;
        adc =< oldBuf.lisa;
        oldBuf.lisa =< preFX;

        buf @=> bufs[p];

        // TODO: maybe should check if they are connected already?
        // connect to the adc & dac
        adc.chan(adc_channel) => bufs[p].lisa => preFX;

        return oldBuf;
    }

    fun void popBuf(LiSaBuf @vacantBuf) {
        // disconnect to the adc & dac
        adc =< bufs[p].lisa;
        bufs[p].lisa =< preFX;

        // clear the vacantBuf
        vacantBuf.clear();

        vacantBuf @=> bufs[p];

        // connect the vacantBuf to the adc & dac
        adc.chan(adc_channel) => bufs[p].lisa => preFX;

        (p - 1) % MAX_BUFFER => p;
    }

    fun void popSelf() {
        // this is different from popBuf that we don't need to disconnect the pipeline
        // just clear the lisa buffer and rotate the pointer
        bufs[p].clear();

        (p - 1) % MAX_BUFFER => p;
    }

    fun void playLoop(int id) {
        bufs[id] @=> LiSaBuf buf;
        buf.playLoop();
    }

    fun void fadeBufsOut() {
        for (int i; i < bufs.size(); i++) {
            spork ~ bufs[i].fadeOut();
        }
    }
    fun void fadeBufsIn() {
        for (int i; i < bufs.size(); i++) {
            spork ~ bufs[i].fadeIn();
        }
    }

    fun void startMonologue() {
        for(int i; i < N; i++) {
            monologueBuf[i].gain(2.5);
            monologueBuf[i].pos(0);
            monologueBuf[i].play();
        }
        while (true) {
            samp => now;
        }
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
oin.addAddress("/player/quantize");
oin.addAddress("/player/monologue");

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
    if(ps[ID].mode == 0) {
        for (int i; i < N; i++) {
            if (ps[i].ID == ID) {

                Math.map2(x_pos, -1, 1, 0.0001, 2) => float shift_amt;
                Math.clampf(Math.map2(z_pos, 0, .4, 0, 1.0), 0, 1.0) => float fx_mix;
                // chout <= "current shift: " <= shift_amt <= IO.newline();

                // Math.map2(y_pos, -1, 1, 3000, 800) => float delay_ms;
                // chout <= "current delay: " <= delay_ms <= IO.newline();

                // Math.map2(x_pos, -1, 1, .8, 4.0) => float rateScaling;
                // chout <= "current interval scaling: " <= intervalScaling <= IO.newline();
                Math.map2(y_pos, -1, 1, 0.0, 1.0) => float plinky_amt;

                for (int j; j < MAX_BUFFER; j++) {
                    ps[i].pitchS[j].mix(fx_mix);
                    ps[i].pitchS[j].shift(shift_amt);

                    ps[i].pRev[j].mix(fx_mix);
                    ps[i].pRev[j].shim(plinky_amt);
                    ps[i].pRev[j].wobble(plinky_amt);

                    ps[i].bufs[j].MAX_GAIN_BASE + fx_mix * .01 => ps[i].bufs[j].MAX_GAIN;

                    // delay_ms::ms => ps[i].echoA[j].delay => ps[i].echoB[j].delay =>
                    // ps[i].echoC[j].delay;
                    // delay_ms::ms => ps[i].delayL[j].max => ps[i].delayL[j].delay;
                    // delay_ms::ms => ps[i].echoA[j].delay => ps[i].echoB[j].delay =>

                    // intervalScaling => ps[i].bufs[j].durationScalingFactor;

                    // rateScaling => ps[i].bufs[j].playbackRate;
                }
            }
        }
    }
    else if(ps[ID].mode == 1) {
        for(int i; i < N; i++) {
            if (ps[i].ID == ID) {
                Math.map2(y_pos, -1, 1, 1.0, 0.0) => float y_norm;
                Math.map2(z_pos, 0, .8, 0.0, 1.0) => float z_norm;

                for(int j; j < N; j++)
                {
                    ps[i].chorus[j].mix(z_norm * .6);
                    ps[i].chorus[j].modDepth(y_norm * .25);
                    if(j != ID){
                        ps[i].monologueBuf[j].gain(y_norm * 2.5);
                    }
                }
            }
        }
    }
}

fun void handleRecord(int ID, int toggle) {
    for (int i; i < N; i++) {
        if (ps[i].ID == ID) {
            // the top buffer of that ps
            ps[i].topBuf() @=> LiSaBuf @buf;

            if (toggle) {
                ps[i].fadeBufsOut();
                now => buf.recStart;
                0::ms => buf.recDuration;
                0::ms => buf.qtDuration;
                buf.clear();
                chout <= "recording started for player " <= ID <= IO.newline();
                buf.lisa.record(true);
            } else {
                chout <= "recording stopped for player " <= ID <= IO.newline();
                now - buf.recStart => buf.recDuration;
                // also calculate the quantization
                buf.setQuantize();
                buf.lisa.record(false);
                ps[i].fadeBufsIn();
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

fun void handleQuantize() {
    if (!qtStatus.on) {
        // quantize turn on
        <<< "QUANTIZE ON" >>>;
        qtStatus.setOn();
        // set the quantize duration for each buffer
        for (int i; i < N; i++) {
            for (int j; j < MAX_BUFFER; j++) {
                ps[i].bufs[j].setQuantize();
            }
        }
    } else if (qtStatus.on) {
        // quantize turn off
        <<< "QUANTIZE OFF" >>>;
        qtStatus.setOff();
    }
}

fun void startMonologue() {
    <<< "Starting Monologue" >>>;
    // also turn of quantize
    qtStatus.setOff();

    for (int i; i < N; i++) {
        for (int j; j < ps[i].bufs.size(); j++) {
            ps[i].bufs[j].clear();
        }
        // start monologue for each player
        spork ~ ps[i].startMonologue();
        1 => ps[i].mode;

        // lower gain of LiSa bufs
        // for (int j; j < ps[i].bufs.size(); j++) {
        //     .25 => ps[i].bufs[j].MAX_GAIN_BASE;
        // }
    }
}

fun void playerListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            // chout <= "received message: " <= msg.address <= IO.newline();
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
                    if(toggle != ps[ID].RECORDING)
                    {
                        handleRecord(ID, toggle);
                        string recordState;
                        if (toggle)
                            "ON" => recordState;
                        else
                            "OFF" => recordState;
                        chout <= "player " <= ID <= " recording state: " <= recordState <= IO.newline();
                        toggle => ps[ID].RECORDING;
                    }
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
                    // chout <= "popping buf from: " <= ID <= IO.newline();
                }
            }

            if (msg.address == "/player/quantize") {
                if (msg.typetag == "i") {
                    // msg.getInt(0) => int quantize;
                    handleQuantize();
                }
            }
            if (msg.address == "/player/monologue") {
                if (msg.typetag == "i") {
                    startMonologue();
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
