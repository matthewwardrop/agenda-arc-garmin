import Toybox.Application;
import Toybox.Background;
import Toybox.System;
import Toybox.Timer;

(:background)
class AgendaArcServiceDelegate extends System.ServiceDelegate {

    var app;
    var calendarClient;

    function initialize() {
        app = Application.getApp();
        calendarClient = app.calendarClient;
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
    }

    public function onTemporalEvent() as Void {
        self.doSync();
    }

    function doSync() {
        switch (calendarClient.loginState) {
            case GoogleCalendarClient.LOGIN_STATE_SIGNED_IN:
                app.calendarClient.sync(method(:onCalendarAuthCallback));
                break;
            default:
                app.calendarClient.signIn(method(:onSignInAttempt));
        }
    }

    function onSignInAttempt(status) {
        self.doSync();
    }


    function onCalendarAuthCallback(status) {
        Background.exit(status);
    }

}
