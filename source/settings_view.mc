import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class AgendaSettingsView extends WatchUi.Menu2 {
    var app;
    var calendarClient;
    var showTimer;

    function initialize() {
        app = Application.getApp();
        showTimer = new Timer.Timer();
        calendarClient = app.calendarClient;
        Menu2.initialize({ :title => "Settings" });

        self.addItem(
            new MenuItem("Checking connection...", null, :connectionStatus, {})
        );
        self.addItem(new MenuItem("Calendars", null, :calendarSelection, {}));
        self.addItem(
            new MenuItem(
                "All Day Events",
                null,
                :calendarIncludeAllDayEvents,
                {}
            )
        );
        self.addItem(
            new MenuItem("Number of hours shown", null, :nHoursShown, {})
        );
    }

    function onShow() {
        self.updateConnectionStatus(calendarClient.syncState().loginState);
        self.getItem(self.findItemById(:calendarSelection)).setSubLabel(
            calendarClient.selectedCalendars.size() + " selected"
        );

        var calendarIncludeAllDayEvents = app.Storage.getValue(
            "calendarIncludeAllDayEvents"
        );
        if (calendarIncludeAllDayEvents == null) {
            calendarIncludeAllDayEvents = false;
        }
        self.getItem(
            self.findItemById(:calendarIncludeAllDayEvents)
        ).setSubLabel(calendarIncludeAllDayEvents ? "shown" : "hidden");

        var nHoursShown = app.Storage.getValue("nHoursShown");
        if (nHoursShown == null) {
            nHoursShown = 8;
        }
        self.getItem(self.findItemById(:nHoursShown)).setSubLabel(
            nHoursShown.toString() + " hours"
        );
    }

    function updateConnectionStatus(loginState) {
        var item = self.getItem(self.findItemById(:connectionStatus));

        switch (loginState) {
            case GoogleCalendarClient.LOGIN_STATE_SIGNED_IN:
                item.setLabel("Connected");
                item.setSubLabel("Tap to disconnect.");
                break;
            case GoogleCalendarClient.LOGIN_STATE_SIGNED_OUT:
                item.setLabel("Not Connected");
                item.setSubLabel("Tap to start login flow.");
                break;
            case GoogleCalendarClient.LOGIN_STATE_PENDING_AUTH_CODE:
                item.setLabel(calendarClient.userCode);
                item.setSubLabel("http://google.com/device/");
                break;
            case GoogleCalendarClient.LOGIN_STATE_AWAITING_AUTH_CODE:
                item.setLabel("Generating code...");
                item.setSubLabel("http://google.com/device/");
                break;
            default:
                item.setLabel("Invalid connection.");
                item.setSubLabel(null);
        }

        WatchUi.requestUpdate();

        showTimer.start(method(:onShow), 5000, false);
    }
}

class AgendaSettingsViewInputDelegate extends WatchUi.Menu2InputDelegate {
    var settingsView;

    function initialize(settingsView) {
        self.settingsView = settingsView;
        Menu2InputDelegate.initialize();
    }

    function onSelect(menuItem) {
        var app = Application.getApp();
        switch (menuItem.getId()) {
            case :connectionStatus:
                switch (app.calendarClient.loginState) {
                    case GoogleCalendarClient.LOGIN_STATE_SIGNED_OUT:
                        app.startSyncing();
                        settingsView.onShow();
                        break;
                    case GoogleCalendarClient.LOGIN_STATE_SIGNED_IN:
                        app.calendarClient.signOut();
                        settingsView.onShow();
                }
                break;
            case :calendarSelection:
                WatchUi.pushView(
                    new CalendarSelectionMenu(),
                    new CalendarSelectionMenuInputDelegate(),
                    WatchUi.SLIDE_UP
                );
                break;
            case :calendarIncludeAllDayEvents:
                var includeAllDayEvents = app.Storage.getValue(
                    "calendarIncludeAllDayEvents"
                );
                if (includeAllDayEvents == null) {
                    app.Storage.setValue("calendarIncludeAllDayEvents", true);
                } else {
                    app.Storage.setValue(
                        "calendarIncludeAllDayEvents",
                        !includeAllDayEvents
                    );
                }
                settingsView.onShow();
                break;
            case :nHoursShown:
                WatchUi.pushView(
                    new HoursShownSelectionMenu(),
                    new HoursShownSelectionMenuInputDelegate(),
                    WatchUi.SLIDE_UP
                );
                break;
        }
    }

    function onLoginStatus(status) {
        settingsView.updateConnectionStatus(status);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onDone() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class CalendarSelectionMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Calendars" });

        var app = Application.getApp();

        for (var i = 0; i < app.calendarClient.calendars.size(); i++) {
            var calendarInfo = app.calendarClient.calendars.values()[i];
            var isSelected =
                app.calendarClient.selectedCalendars.indexOf(
                    calendarInfo["id"]
                ) >= 0;
            self.addItem(
                new IconMenuItem(
                    calendarInfo["name"],
                    calendarInfo["id"],
                    calendarInfo["id"],
                    new CalendarCheck(calendarInfo["color"], isSelected),
                    {}
                )
            );
        }
    }

    hidden var _counter = 0;

    function onTimer() {
        if (_counter < 5) {
            ++_counter;
            addItem(new WatchUi.MenuItem("Blah!", null, null, null));

            // should see updates to sub-label and new items
            WatchUi.requestUpdate();
        }
    }
}

class CalendarSelectionMenuInputDelegate extends WatchUi.Menu2InputDelegate {
    var calendarClient;

    function initialize() {
        Menu2InputDelegate.initialize();

        calendarClient = Application.getApp().calendarClient;
    }

    function onSelect(menuItem) {
        var calendarId = menuItem.getId();
        var isSelected =
            calendarClient.selectedCalendars.indexOf(calendarId) >= 0;

        calendarClient.toggleSelectedCalendar(calendarId);

        menuItem.setIcon(
            new CalendarCheck(
                calendarClient.calendars[calendarId]["color"],
                !isSelected
            )
        );
        WatchUi.requestUpdate();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onDone() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class HoursShownSelectionMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => "Number of hours shown" });

        for (var i = 4; i <= 24; i++) {
            self.addItem(
                new WatchUi.MenuItem(i.toString() + " hours", null, i, null)
            );
        }
    }
}

class HoursShownSelectionMenuInputDelegate extends WatchUi.Menu2InputDelegate {
    function onSelect(menuItem) {
        Storage.setValue("nHoursShown", menuItem.getId());
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
