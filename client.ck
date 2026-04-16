@import "control.ck"

// for (int i; i < 6; i++) {
//     adc.chan(0) => dac.chan(i);
// }

// better localization: only the top speaker
adc.chan(0) => dac.chan(5);

GG.camera().orthographic();

0 => int id;
"192.168.186.82" => string server;

if (me.args()) {
    me.arg(0) => Std.atoi => id;
    me.arg(1) => server;
}

// Set your ID and server IP here
GameTrak gt(id, server);
spork ~ gt.update();
spork ~ gt.throwListener();
spork ~ gt.catchListener();
spork ~ gt.kbListener();

while (true) {
    GG.nextFrame() => now;
}
