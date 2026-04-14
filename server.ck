// Initialize player states
//----------------------------------------------------------------------------
// number of players
3 => int N;

if (me.args()) {
    me.arg(0) => Std.atoi => N;
}

PlayerState ps[N];

class PlayerState {
    // Player ID, 1-indexed
    int ID;
    // Whether the player is ready to catch
    int catchReady;

    // Which ADC channel the player is on
    int adc_channel;

    // Blackhole DAC channel
    int dac_channel;

    int target_channel;

    fun PlayerState(int id) { init(id); }

    fun void init(int id) {
        id => ID;
        id => adc_channel;
        id + 8 => dac_channel;
        dac_channel => target_channel;
    }
}

// Initialize N players, ID = i, ADC = i, DAC = i + 8
for (int i; i < N; i++) {
    ps[i].init(i);
}

// CLIENT -> SERVER
//----------------------------------------------------------------------------
OscIn oin;
OscMsg msg;

8000 => oin.port;

oin.addAddress("/player/throw");
oin.addAddress("/player/catch");

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

fun void playerListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
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
        }
    }
}

spork ~ playerListener();

// SERVER -> CLIENT
//----------------------------------------------------------------------------
// destination port number
6449 => int port;

// array of destination hostnames
string hostnames[0];

//----------------------------------------------------------------------------
// appending names of destinations
//----------------------------------------------------------------------------

// hostnames << "localhost";
// Alex 192.168.180.1
hostnames << "192.168.176.224"; // Summer
hostnames << "192.168.186.82";  // Lejun

// sender object
OscOut xmit[hostnames.size()];
// iterate over the OSC transmitters
for (int i; i < xmit.size(); i++) {
    // aim the transmitter at destination
    xmit[i].dest(hostnames[i], port);
}

fun void routeAudio(int source, int target, int oldTarget) {
    chout <= "routing audio from ADC channel " <= source <= " to DAC channel " <= target <=
        IO.newline();
    adc.chan(source) =< dac.chan(oldTarget);
    adc.chan(source) => dac.chan(target);
}


while (true) {
    second => now;
}
