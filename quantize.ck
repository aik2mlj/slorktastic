public class QuantizeStatus {
    dur loopDur;
    int on;
    float allowedMeters[] = [1 / 4, 1 / 3];

    fun void init(dur d) { d => loopDur; }

    fun void setOn(dur d) {
        1 => on;
        d => loopDur;
    }
    fun void setOff() { 0 => on; }

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
