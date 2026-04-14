@import "control.ck"

GG.camera().orthographic();

// Set your ID and server IP here
GameTrak gt(0, "192.168.180.1");
spork ~ gt.update();
spork ~ gt.throwListener();
spork ~ gt.catchListener();

while (true) {
    GG.nextFrame() => now;
}
