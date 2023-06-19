import Toybox.System;
import Toybox.Math;

function drawFractionalArc(dc, x, y, r, direction, angleA, angleB) {
    var start = min(angleA, angleB);
    var end = max(angleA, angleB);

    if (Math.ceil(start) < Math.floor(end)) {
        dc.drawArc(x, y, r, direction, Math.ceil(start), Math.floor(end));
    }

    var x1 = arcPoint(x, y, r, direction, start);
    var x2 = arcPoint(x, y, r, direction, min(end, Math.ceil(start)));

    dc.drawLine(x1[0], x1[1], x2[0], x2[1]);

    x1 = arcPoint(x, y, r, direction, max(start, Math.floor(end)));
    x2 = arcPoint(x, y, r, direction, end);
    dc.drawLine(x1[0], x1[1], x2[0], x2[1]);
}

function arcPoint(x, y, r, direction, theta) {
    return [
        Math.floor(x + r * Math.cos((Math.PI * theta) / 180)),
        Math.ceil(
            y + (2 * direction - 1) * r * Math.sin((Math.PI * theta) / 180)
        ),
    ];
}
