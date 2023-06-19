import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

import Toybox.Graphics;

class CalendarCheck extends WatchUi.Drawable {
    var color;
    var selected as Lang.Boolean;

    public function initialize(color, selected as Lang.Boolean) {
        Drawable.initialize({});
        self.color = color;
        self.selected = selected;
    }

    public function draw(dc as Dc) as Void {
        var radius = min(dc.getWidth(), dc.getHeight()) / 2;
        var x = dc.getWidth() / 2;
        var y = dc.getHeight() / 2;

        dc.setColor(self.color, dc.COLOR_BLACK);
        dc.setPenWidth(6);
        if (self.selected) {
            dc.fillCircle(x, y, radius);
        } else {
            dc.drawCircle(x, y, radius);
        }
    }
}
