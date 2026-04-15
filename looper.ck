adc => LiSa buf => dac;

1::second => dur MAX_BUFFER_DURATION;
8 => int NUM_VOICES;
20::ms => dur RAMP_TIME;

MAX_BUFFER_DURATION => buf.duration;
NUM_VOICES => buf.maxVoices;
RAMP_TIME => buf.recRamp;


fun void play(float startPos, float gain, float rate, dur duration) {
    while (true) {
        buf.getVoice() => int v;
        if (v < 0)
            return;

        buf.voiceGain(v, gain);
        buf.rate(v, rate);
        buf.loop(v, 1);

        <<< "ATTACK" >>>;
        buf.playPos(v, startPos::samp);

        buf.rampUp(v, RAMP_TIME);
        RAMP_TIME => now;

        <<< "SUSTAIN" >>>;
        duration - 2 * RAMP_TIME => now;

        buf.rampDown(v, RAMP_TIME);
        <<< "RELEASE" >>>;
        RAMP_TIME => now;
    }
}

false => int RECORDING;
now => time recordingStart;
dur recordingDuration;

Hid hi;
HidMsg msg;
if (!hi.openKeyboard(0))
    me.exit();
<<< "keyboard '" + hi.name() + "' ready", "" >>>;

fun void kbListener() {
    // infinite event loop
    while (true) {
        // wait on event
        hi => now;

        // get one or more messages
        while (hi.recv(msg)) {
            // check for action type
            if (msg.isButtonDown() && msg.key == 44 && !RECORDING) {
                // <<< "down:", msg.which, "(code)", msg.key, "(usb key)", msg.ascii, "(ascii)" >>>;
                true => RECORDING;
                now => recordingStart;
                <<< "RECORDING ON" >>>;
                buf.record(true);
            } else {
                if (msg.key == 44 && RECORDING) {
                    false => RECORDING;
                    now - recordingStart => recordingDuration;
                    <<< "recording duration:", recordingDuration >>>;
                    <<< "RECORDING OFF" >>>;
                    buf.record(false);
                    // spork ~ play(0, .5, 1, recordingDuration);
                }
            }
        }
    }
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
        recordingDuration - 2 * RAMP_TIME => now;

        buf.rampDown(v, RAMP_TIME);
        <<< "RELEASE" >>>;
        RAMP_TIME => now;
    }
}

spork ~ playLoop();
spork ~ kbListener();


while (true) {
    second => now;
}