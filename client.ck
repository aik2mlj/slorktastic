@import "control.ck"

for (int i; i < 6; i++) {
    adc.chan(0) => dac.chan(i + 16);
}

// better localization: only the top speaker
adc.chan(0) => dac.chan(5);

GG.camera().orthographic();

0 => int id;
"192.168.186.82" => string server;
int kb_device;
string kb_name;
if (me.args()) {
    me.arg(0) => Std.atoi => id;
    me.arg(1) => server;
    me.arg(2) => Std.atoi => kb_device;
}

// Set your ID and server IP here
GameTrak gt(id, server, kb_device);
spork ~ gt.update();
spork ~ gt.throwListener();
spork ~ gt.continuousControlListener();
spork ~ gt.kbListener();
spork ~ gt.continuousRecordBroadcast();

while (true) {
    GG.nextFrame() => now;
}
