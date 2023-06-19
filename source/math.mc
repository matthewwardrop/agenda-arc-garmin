import Toybox.Math;

function abs(value) {
    return Math.sqrt(Math.pow(value, 2));
}

function min(value1, value2) {
    if (value1 < value2) {
        return value1;
    }
    return value2;
}

function max(value1, value2) {
    if (value1 > value2) {
        return value1;
    }
    return value2;
}

// Circular Geometry

function min_displacement(radius, width) {
    return radius * (1 - Math.sin(Math.acos(width / 2 / radius)));
}

function max_width(radius, displacement) {
    return 2 * radius * Math.sin(Math.acos(1 - displacement / radius));
}
