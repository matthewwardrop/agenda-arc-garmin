import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Complications;
import Toybox.System;
import Toybox.Time;

(:background)
public class AgendaArcApp extends Application.AppBase {
    var calendarClient;

    function initialize() {
        AppBase.initialize();
        calendarClient = new GoogleCalendarClient();
        if (
            calendarClient.loginState !=
            GoogleCalendarClient.LOGIN_STATE_SIGNED_OUT
        ) {
            self.startSyncing();
        }
    }

    (:background)
    function isBackground() {
        try {
            AgendaArcApp.getApp().setProperty("dsfg94339fj2e9485hduth3", false);
            AgendaArcApp.getApp().deleteProperty("dsfg94339fj2e9485hduth3");

            return false;
        } catch (ex) {
            return true;
        }
    }

    function startSyncing() {
        Background.registerForTemporalEvent(new Time.Duration(5 * 60));
    }

    function stopSyncing() {
        Background.registerForTemporalEvent(null);
    }

    function onStart(params as Dictionary) as Void {
        if (!self.isBackground()) {
            // Register a callback for receiving
            // updates on complication information
            Complications.registerComplicationChangeCallback(
                method(:onComplicationChanged)
            );

            // // Liking and subscribing
            Complications.subscribeToUpdates(
                new Id(Complications.COMPLICATION_TYPE_HEART_RATE)
            );
        }
    }

    function onComplicationChanged(complicationId) as Void {
        var complication = Complications.getComplication(complicationId);
        var currentView = WatchUi.getCurrentView()[0];

        if (currentView instanceof AgendaArcFace && complication != null) {
            currentView.currentHeartRate = complication.value;
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {}

    // Return the initial view of your application here
    function getInitialView() as Array<Views or InputDelegates>? {
        return (
            [new AgendaArcFace(), new AgendaArcFaceDelegate()] as
            Array<Views or InputDelegates>
        );
    }

    // Return the settings view
    function getSettingsView() as Array<Views or InputDelegates>? {
        var settingsView = new AgendaSettingsView();
        return (
            [settingsView, new AgendaSettingsViewInputDelegate(settingsView)] as
            Array<Views or InputDelegates>
        );
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

    public function getServiceDelegate() as Array<ServiceDelegate> {
        return [new AgendaArcServiceDelegate()];
    }

    function onBackgroundData(data) {
        calendarClient.syncState();

        var currentView = WatchUi.getCurrentView()[0];
        if (currentView instanceof AgendaArcFace) {
            currentView.displayInvalidated = true;
        }

        WatchUi.requestUpdate();
    }
}

function getApp() as AgendaArcApp {
    return Application.getApp() as AgendaArcApp;
}
