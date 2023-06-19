import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Complications;
import Toybox.Math;
import Toybox.Time;

class AgendaArcFace extends WatchUi.WatchFace {
    var app;
    var backgroundLayer;
    var eventArcLayer;
    var textLayer;
    var myTextArea;
    var nHours = 8;
    var nowOffset = 0.1;

    var eventArcRadiusMultiplier = 3.0;
    var eventArcRadius;
    var minArcAngle;
    var maxArcAngle;

    var bgUpdated = false;

    var currentEvent = null;
    var currentEventUpdatedAt = null;
    var displayInvalidated = true;

    var currentHeartRate = null;

    var currentTime = null;
    var currentClockTime = null;

    function initialize() {
        self.app = Application.getApp();
        WatchFace.initialize();
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        dc.clear();

        backgroundLayer = new WatchUi.Layer({
            :x => 0,
            :y => 0,
            :width => dc.getWidth(),
            :height => dc.getHeight(),
        });
        addLayer(backgroundLayer);

        eventArcLayer = new WatchUi.Layer({
            :x => 0,
            :y => 0,
            :width => dc.getWidth(),
            :height => dc.getHeight(),
        });
        addLayer(eventArcLayer);

        textLayer = new WatchUi.Layer({
            :x => 0,
            :y => 0,
            :width => dc.getWidth(),
            :height => dc.getHeight(),
        });
        addLayer(textLayer);

        myTextArea = new WatchUi.TextArea({
            :text => "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
            :color => Graphics.COLOR_WHITE,
            :font => [
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_XTINY,
            ],
            :locX => dc.getWidth() / 2,
            :locY => dc.getHeight() / 2,
            :width => dc.getWidth() / 2,
            :height => dc.getWidth() / 2,
        });

        var settings = System.getDeviceSettings();

        var angleDev;
        if (
            settings.screenShape == System.SCREEN_SHAPE_ROUND ||
            settings.screenShape == System.SCREEN_SHAPE_SEMI_ROUND
        ) {
            angleDev =
                (Math.acos(1.0 - 0.5 / Math.pow(eventArcRadiusMultiplier, 2)) *
                    180.0) /
                Math.PI;
        } else {
            angleDev =
                (Math.asin(1.0 / eventArcRadiusMultiplier) * 180.0) / Math.PI;
        }
        minArcAngle = 90.0 + angleDev;
        maxArcAngle = 90.0 - angleDev;

        eventArcRadius = (dc.getHeight() / 2.0) * eventArcRadiusMultiplier;
    }

    function onShow() as Void {
        bgUpdated = false;

        var nHoursShown = Storage.getValue("nHoursShown");
        if (nHoursShown != null) {
            nHours = nHoursShown;
        }
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Void {
        var screenWidth = System.getDeviceSettings().screenWidth;

        if (clickEvent.getCoordinates()[0] < screenWidth / 2) {
            self.nextCurrentEvent(-1);
        } else {
            self.nextCurrentEvent(1);
        }

        displayInvalidated = true;
        WatchUi.requestUpdate();
    }

    function getCurrentEventTimeWindow() {
        var eventTimeWindow = new Array<Number>[2];

        var now = self.currentTime;
        if (now == null) {
            now = Time.now();
        }

        eventTimeWindow[0] =
            now.value() - (nowOffset * nHours * 3600).toNumber();
        eventTimeWindow[1] =
            now.value() + ((1 - nowOffset) * nHours * 3600).toNumber();

        return eventTimeWindow;
    }

    function getCurrentEvent() {
        var calendar_events = self.app.calendarClient.getEvents();

        if (
            self.currentEvent != null &&
            self.currentEventUpdatedAt > Time.now().value() - 60
        ) {
            return self.currentEvent;
        }

        if (calendar_events.size() == 0) {
            return null;
        }

        for (var i = 0; i < calendar_events.size(); i++) {
            var event = calendar_events[i];

            var startTime = event["start"];

            if (startTime != null && startTime > Time.now().value() - 5 * 60) {
                return event;
            }
        }

        return calendar_events[calendar_events.size() - 1];
    }

    function nextCurrentEvent(offset) {
        var events = self.app.calendarClient.getEvents();

        if (events.size() == 0) {
            self.currentEvent = null;
            return;
        }

        var currentEvent = self.getCurrentEvent();
        var currentIndex = 0;
        if (currentEvent != null) {
            currentIndex = events.indexOf(currentEvent);
        }

        if (currentIndex < 0) {
            currentIndex = 0;
        } else {
            currentIndex = (currentIndex + offset) % events.size();
            while (currentIndex < 0) {
                currentIndex += events.size();
            }
        }

        self.currentEvent = events[currentIndex];
        self.currentEventUpdatedAt = Time.now().value();
        return self.currentEvent;
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // dc.clear(); // Needed in simulator, but breaks things on real device

        currentTime = Time.now();
        var clockTime = System.getClockTime();

        // Get the current time and format it correctly
        var timeFormat = "$1$:$2$";

        var hours = clockTime.hour;
        if (!System.getDeviceSettings().is24Hour) {
            if (hours > 12) {
                hours = hours - 12;
            }
        } else {
            if (getApp().getProperty("UseMilitaryFormat")) {
                timeFormat = "$1$$2$";
                hours = hours.format("%02d");
            }
        }
        var timeString = Lang.format(timeFormat, [
            hours,
            clockTime.min.format("%02d"),
        ]);

        // Set time and date text
        var textDc = textLayer.getDc();
        textDc.clear();
        textDc.setColor(dc.COLOR_WHITE, dc.COLOR_TRANSPARENT);

        var timeInfo = Gregorian.info(currentTime, Gregorian.FORMAT_MEDIUM);

        var dateStr = Lang.format("$1$, $2$ $3$", [
            timeInfo.day_of_week,
            timeInfo.month,
            timeInfo.day,
        ]);

        var textDim = textDc.getTextDimensions(dateStr, dc.FONT_XTINY);
        var textDim2 = textDc.getTextDimensions(timeString, dc.FONT_LARGE);

        var disp = min_displacement(
            dc.getHeight(),
            Math.round(textDim[0] / 100 + 1) * 100
        );
        textDc.drawText(
            textDc.getWidth() / 2,
            disp + 0.05 * dc.getHeight(),
            dc.FONT_XTINY,
            dateStr,
            dc.TEXT_JUSTIFY_CENTER
        );

        textDc.drawText(
            textDc.getWidth() / 2,
            disp + textDim[1] + 0.12 * dc.getHeight(),
            dc.FONT_LARGE,
            timeString,
            dc.TEXT_JUSTIFY_CENTER + dc.TEXT_JUSTIFY_VCENTER
        );

        // HEART RATE TEXT
        if (currentHeartRate != null) {
            textDc.drawText(
                textDc.getWidth() / 2,
                disp + textDim[1] + 0.06 * dc.getHeight() + textDim2[1],
                dc.FONT_XTINY,
                "HR " + currentHeartRate.toString(),
                dc.TEXT_JUSTIFY_CENTER + dc.TEXT_JUSTIFY_VCENTER
            );
        }

        if (timeString.equals(currentClockTime) && !displayInvalidated) {
            return;
        }

        currentClockTime = timeString;
        displayInvalidated = false;

        // Update the background
        if (!bgUpdated) {
            backgroundLayer
                .getDc()
                .setColor(dc.COLOR_WHITE, dc.COLOR_TRANSPARENT);
            backgroundLayer.getDc().setPenWidth(3);
            self.drawFractionalArc(
                backgroundLayer.getDc(),
                dc.getWidth() / 2,
                eventArcRadius + dc.getHeight() / 2,
                eventArcRadius,
                dc.ARC_COUNTER_CLOCKWISE,
                minArcAngle,
                maxArcAngle
            );
            bgUpdated = true;
        }

        var eventDc = eventArcLayer.getDc();
        eventDc.setColor(eventDc.COLOR_WHITE, eventDc.COLOR_TRANSPARENT);
        eventDc.clear();

        eventDc.setPenWidth(6);
        if (eventDc has :setAntiAlias) {
            eventDc.setAntiAlias(true);
        }

        var client = app.calendarClient;
        var calendar_events = client.events;

        if (calendar_events == null) {
            calendar_events = {};
        }

        var getCurrentEventTimeWindow = self.getCurrentEventTimeWindow();
        var minUTCTimestamp = getCurrentEventTimeWindow[0];
        var maxUTCTimestamp = getCurrentEventTimeWindow[1];

        calendar_events = client.getEvents();

        var currentEventInfo = self.getCurrentEvent();

        var bandOccupancy = {};

        for (var i = 0; i < calendar_events.size(); i++) {
            var event = calendar_events[i];

            var startTime = event["start"];
            var endTime = event["end"];

            eventDc.setColor(event["color"], eventDc.COLOR_TRANSPARENT);

            if (startTime > maxUTCTimestamp || endTime < minUTCTimestamp) {
                continue;
            }

            var startAngle =
                min(
                    minArcAngle,
                    minArcAngle +
                        ((startTime - minUTCTimestamp) / 3600.0 / nHours) *
                            (maxArcAngle - minArcAngle)
                ) as Lang.Float;
            var endAngle =
                max(
                    maxArcAngle,
                    minArcAngle +
                        ((endTime - minUTCTimestamp) / 3600.0 / nHours) *
                            (maxArcAngle - minArcAngle)
                ) as Lang.Float;

            if (event == currentEventInfo) {
                eventDc.setPenWidth(7);
            } else {
                eventDc.setPenWidth(4);
            }

            var eventBand = 1;
            while (
                bandOccupancy.hasKey(eventBand) &&
                bandOccupancy[eventBand] > startTime - 5 * 60
            ) {
                eventBand++;
            }

            bandOccupancy[eventBand] = endTime;

            self.drawFractionalArc(
                eventDc,
                eventDc.getWidth() / 2,
                2 * eventDc.getHeight(),
                eventArcRadius + eventBand * 9,
                eventDc.ARC_COUNTER_CLOCKWISE,
                startAngle,
                endAngle
            );
        }

        currentTime = Time.now();

        eventDc.setColor(dc.COLOR_WHITE, dc.COLOR_TRANSPARENT);
        eventDc.setPenWidth(1);
        var theta =
            minArcAngle -
            ((clockTime.min / 60.0 + clockTime.sec / 3600.0 - 1.0) *
                (maxArcAngle - minArcAngle)) /
                nHours +
            (nowOffset - 1.0 / nHours) * (maxArcAngle - minArcAngle);
        var hour = clockTime.hour;

        while (theta > maxArcAngle) {
            var x1 = arcPoint(
                dc.getWidth() / 2,
                2 * eventDc.getHeight(),
                2 * eventDc.getHeight() - eventDc.getHeight() / 2,
                eventDc.ARC_COUNTER_CLOCKWISE,
                theta
            );
            var x2 = arcPoint(
                dc.getWidth() / 2,
                2 * eventDc.getHeight(),
                2 * eventDc.getHeight() - eventDc.getHeight() / 2 - 15,
                eventDc.ARC_COUNTER_CLOCKWISE,
                theta
            );
            eventDc.drawLine(x1[0], x1[1], x2[0], x2[1]);
            eventDc.drawText(
                x2[0],
                x2[1],
                dc.FONT_XTINY,
                Lang.format("$1$", [hour]),
                dc.TEXT_JUSTIFY_CENTER
            );

            theta =
                theta +
                ((nHours > 12 ? 2 : 1) * (maxArcAngle - minArcAngle)) / nHours;
            hour = (hour + (nHours > 12 ? 2 : 1)) % 24;
        }

        theta = minArcAngle + 0.1 * (maxArcAngle - minArcAngle);
        var x1 = arcPoint(
            dc.getWidth() / 2,
            2 * eventDc.getHeight(),
            2 * eventDc.getHeight() - eventDc.getHeight() / 2,
            eventDc.ARC_COUNTER_CLOCKWISE,
            theta
        );
        var x2 = arcPoint(
            dc.getWidth() / 2,
            2 * eventDc.getHeight(),
            2 * eventDc.getHeight() - eventDc.getHeight() / 2 + 50,
            eventDc.ARC_COUNTER_CLOCKWISE,
            theta
        );
        eventDc.drawLine(x1[0], x1[1], x2[0], x2[1]);

        // Show event info

        if (currentEventInfo != null) {
            var locationTextHeight = eventDc.getTextDimensions(
                currentEventInfo["location"]
                    ? currentEventInfo["location"]
                    : "Location",
                dc.FONT_XTINY
            )[1];
            if (currentEventInfo["location"] != null) {
                eventDc.setColor(
                    Graphics.COLOR_DK_GRAY,
                    Graphics.COLOR_TRANSPARENT
                );
                eventDc.drawText(
                    eventDc.getWidth() / 2,
                    0.95 * dc.getHeight() - disp - textDim[1],
                    dc.FONT_XTINY,
                    currentEventInfo["location"],
                    dc.TEXT_JUSTIFY_CENTER
                );
                eventDc.setColor(
                    Graphics.COLOR_WHITE,
                    Graphics.COLOR_TRANSPARENT
                );
            }

            var eventTitleOffset =
                0.5 * eventDc.getHeight() + disp + 2 * 15 + 25;
            var eventTitleHeight =
                eventDc.getHeight() -
                eventTitleOffset -
                locationTextHeight -
                15;

            var titleTextArea = new WatchUi.TextArea({
                :text => currentEventInfo["title"],
                :justification => dc.TEXT_JUSTIFY_CENTER +
                dc.TEXT_JUSTIFY_VCENTER,
                :locX => (eventDc.getWidth() -
                    max_width(eventDc.getWidth(), disp + textDim[1])) /
                2,
                :locY => eventTitleOffset,
                :width => max_width(eventDc.getWidth(), disp + textDim[1]),
                :height => eventTitleHeight,
                :font => [
                    eventDc.FONT_MEDIUM,
                    eventDc.FONT_TINY,
                    eventDc.FONT_XTINY,
                ],
            });
            titleTextArea.draw(eventDc);
        }
    }
}

class AgendaArcFaceDelegate extends WatchUi.WatchFaceDelegate {
    public function onPress(clickEvent) {
        var watchFace = WatchUi.getCurrentView()[0];
        watchFace.onPress(clickEvent);
    }
}
