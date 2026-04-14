public class GameTrak {
    0 => int ID;
    "192.168.180.1" => string SERVER_IP;

    fun GameTrak(int id, string server_ip) {
        id => ID;
        server_ip => SERVER_IP;
    }

    time lastTime;
    time currTime;
    float lastAxis[6];
    float axis[6];
    float velocity[6];

    0.01 => float DEADZONE;
    .9 => float SMOOTHING_FACTOR;

    // Set up GameTrak
    0 => int device;
    // if (me.args())
    //     me.arg(0) => Std.atoi => device;

    Hid trak;
    if (trak.openJoystick(device)) {
        <<< "GameTrak / joystick:", trak.name(), "on" >>>;
    } else {
        <<< "No joystick — use UI" >>>;
    }

    fun void update() {
        HidMsg msg;
        while (true) {
            trak => now;
            while (trak.recv(msg)) {
                // joystick axis motion
                if (msg.isAxisMotion()) {
                    // check which
                    if (msg.which >= 0 && msg.which < 6) {
                        // check if fresh
                        if (now > currTime) {
                            // time stamp
                            currTime => lastTime;
                            // set
                            now => currTime;
                        }
                        // save last
                        SMOOTHING_FACTOR * velocity[msg.which] +
                            (1.0 - SMOOTHING_FACTOR) * (axis[msg.which] - lastAxis[msg.which]) *
                                (1000) => velocity[msg.which];
                        // (axis[msg.which] - lastAxis[msg.which] ) * (1000) =>
                        // velocity[msg.which];
                        axis[msg.which] => lastAxis[msg.which];
                        // chout <= "velocity: " <= "x = " <= velocity[3] <= " y = " <=
                        // velocity[4] <= " z = " <= velocity[5] <= IO.newline();

                        // chout <= "x: " <= axis[0] <= " y: " <= axis[1] <= " z: " <=
                        // axis[2] <= IO.newline();

                        // the z axes map to [0,1], others map to [-1,1]
                        if (msg.which != 2 && msg.which != 5) {
                            msg.axisPosition => axis[msg.which];
                        } else {
                            1 - ((msg.axisPosition + 1) / 2) - DEADZONE => axis[msg.which];
                            if (axis[msg.which] < 0)
                                0 => axis[msg.which];
                        }
                    }
                }
            }
        }
    }

    GLines line --> GG.scene();
    line.width(.1);

    vec2 start;
    vec2 end;
    int throwing;
    float throw_angle;

    GText catch_text --> GG.scene();
    "" => catch_text.text;
    catch_text.color(@(1, 1, 1));
    catch_text.size(.5);
    catch_text.posY(-1.5);

    GText ID_text --> GG.scene();
    Std.itoa(ID) => ID_text.text;
    ID_text.color(@(1, 1, 1));
    ID_text.size(.5);
    ID_text.posY(1.5);
    ID_text.posX(-1);

    fun void throwListener() {
        while (true) {
            Math.sqrt(Math.pow(velocity[3], 2) + Math.pow(velocity[4], 2)) => float speed;
            // chout <= "speed: " <= speed <= IO.newline();

            // speed crosses threshold for throw start
            if (speed > 30.0) {
                if (!throwing) {
                    // velocity[3] => start.x;
                    // velocity[4] => start.y;
                    true => throwing;
                }
            } else {
                if (throwing) {
                    velocity[3] => end.x;
                    velocity[4] => end.y;
                    false => throwing;

                    Math.atan2(end.y - start.y, end.x - start.x) / Math.PI * 180 => throw_angle;
                    // chout <= "throw angle: " <= throw_angle <= IO.newline();

                    vec2 line_start;
                    vec2 line_end;

                    if (axis[5] > .25 && throw_angle > 0 && throw_angle < 180) {
                        // Math.map2(start.x, -100, 100, -1.5, 1.5) => line_start.x;
                        // Math.map2(start.y, -100, 100, -1.5, 1.5) => line_start.y;
                        Math.map2(end.x, -100, 100, -2, 2) => line_end.x;
                        Math.map2(end.y, -100, 100, -2, 2) => line_end.y;
                        [line_start, line_end] => line.positions;
                        chout <= "throwing with angle: " <= throw_angle <= IO.newline();
                        <<< start.x, start.y, end.x, end.y >>>;
                        sendThrow(throw_angle);
                    }
                }
            }
            // chout <= "velocity: " <= "x = " <= velocity[3] <= " y = " <=
            // velocity[4] <= " z = " <= velocity[5] <= IO.newline();
            10::ms => now;
        }
    }

    false => int catchReady;

    fun void catchListener() {
        while (true) {
            Math.fabs(axis[2] - axis[5]) => float catch_diff;
            .1 => float diff_threshold;

            // chout <= "catch diff: " <= catch_diff <= IO.newline();

            if (catch_diff < diff_threshold && axis[2] > .3 && axis[5] > .3) {
                if (!catchReady) {
                    true => catchReady;
                    "CATCH READY" => catch_text.text;
                    sendCatch(catchReady);
                }
            } else {
                if (catchReady) {
                    false => catchReady;
                    "" => catch_text.text;
                    sendCatch(catchReady);
                }
            }
            10::ms => now;
        }
    }

    OscOut xmit;
    xmit.dest(SERVER_IP, 8000);

    fun void sendThrow(float angle) {
        chout <= "sending throw with angle: " <= angle <= "to server: " <= SERVER_IP <=
            IO.newline();
        xmit.start("/player/throw");
        ID => xmit.add;
        angle => xmit.add;
        xmit.send();
    }

    fun void sendCatch(int ready) {
        chout <= "sending catch with ID: " <= ID <= " ready: " <= ready <= "to server: " <=
            SERVER_IP <= IO.newline();
        xmit.start("/player/catch");
        ID => xmit.add;
        ready => xmit.add;
        xmit.send();
    }
}
