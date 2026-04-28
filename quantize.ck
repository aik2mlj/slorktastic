public class QuantizeStatus {
    // default value of loopDur
    0.5::second => dur DEFAULT_LOOPDUR;

    DEFAULT_LOOPDUR => dur loopDur;
    1 => int on;
    [0.5] @=> float allowedMeters[];

    SndBuf kick;
    me.dir() + "audio/kick.wav" => kick.read;
    0 => kick.gain;

    // connect to every channel
    for (8 => int i; i < dac.channels(); i++) {
        kick => dac.chan(i);
    }

    fun void setOn() { setOn(DEFAULT_LOOPDUR); }

    fun void setOn(dur d) {
        1 => on;
        d => loopDur;
        0.2 => kick.gain;
    }
    fun void setOff() {
        1 => on;
        0 => kick.gain;
    }

    fun void playKickLoop() {
        while (true) {
            if (on) {
                <<< "playing kick" >>>;
                0 => kick.pos;
                loopDur => now;
            } else {
                100::ms => now;
            }
        }
    }

    fun dur getQuantizedDur(dur d) {
        if (d == 0::samp)
            return d;
        100 => float minOffset;
        dur quantizedDur;
        // snap the duration to the nearest multitude of allowed meter times loopDur
        for (0 => int i; i < allowedMeters.size(); i++) {
            allowedMeters[i] * loopDur => dur allowedDurUnit;
            // get the multitudes of allowedDurUnit that is closest to d
            (d / allowedDurUnit + 0.5) $ int => int mult;
            if (Math.fabs((mult * allowedDurUnit - d) / 1::second) < minOffset) {
                mult * allowedDurUnit => quantizedDur;
                Math.fabs((quantizedDur - d) / 1::second) => minOffset;
            }
        }
        return quantizedDur;
    }
}
