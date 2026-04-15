//-----------------------------------------------------------------------------
// name: lisa-mic.ck
// desc: gametrak-controlled granular mic sampler;
//       records live mic input into a LiSa buffer via foot pedal,
//       then uses tether axes to scrub through and resynthesize
//       captured audio with variable rate, gain, and position
//
// author: Lejun Min
// date: spring 2026
//-----------------------------------------------------------------------------

// z axis deadzone
0.01 => float DEADZONE;

// which joystick
0 => int device;
// get from command line
if (me.args())
    me.arg(0) => Std.atoi => device;

// HID objects
Hid trak;
HidMsg msg;

// open joystick 0, exit on fail
if (!trak.openJoystick(device))
    me.exit();

// print
<<< "joystick '" + trak.name() + "' ready", "" >>>;

// data structure for gametrak
class GameTrak {
    // timestamps
    time lastTime;
    time currTime;

    // previous axis data
    float lastAxis[6];
    // current axis data
    float axis[6];
}

// gametrack
GameTrak gt;

5::second => dur EXTRACT_DELAY;
6::second => dur MIC_BUFFER_LEN;
0.5::second => dur EXTRACT_TIME;
24 => int NUM_VOICES;

// record mic into LiSa
LiSa6 micBuf;
NRev rev[2];

// --- LiSa rolling recorder ---
MIC_BUFFER_LEN => micBuf.duration;
// multiple playback voices
NUM_VOICES => micBuf.maxVoices;
// random panning
<<< micBuf.channels() >>>;
for (int v; v < micBuf.maxVoices(); v++) {
    // can pan across all available channels
    // note LiSa.pan( voice, [0...channels-1] )
    micBuf.pan(v, Math.random2f(0, micBuf.channels() - 1));
}
// reverb
0.1 => rev[0].mix;
0.1 => rev[1].mix;

adc => micBuf => rev => dac;
// start recording!!
// 1 => micBuf.record;

// spork control
spork ~ gametrak();

// main loop
while (true) {
    // print 6 continuous axes -- XYZ values for left and right
    <<< "axes:", gt.axis[0], gt.axis[1], gt.axis[2], gt.axis[3], gt.axis[4], gt.axis[5] >>>;

    // also can map gametrak input to audio parameters around here
    // note: gt.lastAxis[0]...gt.lastAxis[5] hold the previous XYZ values
    // spork ~ synthesizeMic();
    spork ~ synthesizeMic(gt.axis[2] * MIC_BUFFER_LEN / 1::samp, gt.axis[5] * 5.0, gt.axis[0]);

    // advance time
    50::ms => now;
}

fun void synthesizeMic() {
    synthesizeMic(Math.random2f(0, (MIC_BUFFER_LEN - 1::second) / 1::samp),
                  Math.random2f(0.5, 1.0), 1.);
}

fun void synthesizeMic(float startPos, float gain, float rate) {
    // allocate a LiSa voice
    micBuf.getVoice() => int v;
    if (v < 0)
        return;

    micBuf.voiceGain(v, gain);
    micBuf.rate(v, rate);
    micBuf.loop(v, 0);

    // set play position and start
    micBuf.playPos(v, startPos::samp);
    // micBuf.play(v, 1);

    // attack
    micBuf.rampUp(v, EXTRACT_TIME);
    EXTRACT_TIME => now;

    // sustain
    EXTRACT_TIME => now;

    // release
    micBuf.rampDown(v, EXTRACT_TIME);
    EXTRACT_TIME => now;

    // stop voice
    // micBuf.play(v, 0);
}


// gametrack handling
fun void gametrak() {
    while (true) {
        // wait on HidIn as event
        trak => now;

        // messages received
        while (trak.recv(msg)) {
            // joystick axis motion
            if (msg.isAxisMotion()) {
                // check which
                if (msg.which >= 0 && msg.which < 6) {
                    // check if fresh
                    if (now > gt.currTime) {
                        // time stamp
                        gt.currTime => gt.lastTime;
                        // set
                        now => gt.currTime;
                    }
                    // save last
                    gt.axis[msg.which] => gt.lastAxis[msg.which];
                    // the z axes map to [0,1], others map to [-1,1]
                    if (msg.which != 2 && msg.which != 5) {
                        msg.axisPosition => gt.axis[msg.which];
                    } else {
                        1 - ((msg.axisPosition + 1) / 2) - DEADZONE => gt.axis[msg.which];
                        if (gt.axis[msg.which] < 0)
                            0 => gt.axis[msg.which];
                    }
                }
            }

            // joystick button down
            else if (msg.isButtonDown()) {
                <<< "button", msg.which, "down" >>>;
                // start recording
                1 => micBuf.record;
            }

            // joystick button up
            else if (msg.isButtonUp()) {
                <<< "button", msg.which, "up" >>>;
                // stop recording
                0 => micBuf.record;
            }
        }
    }
}
