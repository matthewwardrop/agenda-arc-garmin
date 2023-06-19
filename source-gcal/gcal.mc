import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

(:background)
class GoogleCalendarClient {
    class SyncTask {
        var method;
        var params;

        function initialize(method, params) {
            self.method = method;
            self.params = params;
        }

        function start(callback) {
            return self.method.invoke(params, callback);
        }
    }

    enum LoginState {
        LOGIN_STATE_SIGNED_OUT = 1,
        LOGIN_STATE_AWAITING_AUTH_CODE = 2,
        LOGIN_STATE_PENDING_AUTH_CODE = 3,
        LOGIN_STATE_SIGNED_IN = 4,
    }

    const CLIENT_ID = "YOUR CLIENT ID HERE";
    const CLIENT_SECRET = "YOUR CLIENT SECRET HERE";
    const GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code";

    // Login state and tokens
    var loginState = LOGIN_STATE_SIGNED_OUT;
    var refreshToken;
    var accessToken;
    var accessTokenExpiry;
    var deviceCode;
    var userCode;
    var userCodeExpiry;

    // Calendar information
    var calendars = {};
    var colors = {};
    var selectedCalendars = [];

    // Events and information
    var events = {};
    var sortedEvents = [];

    // Working variables
    var pendingSyncTasks;

    function initialize() {
        self.restoreTokens();
        self.restoreData();
    }

    /* Top-level public entrypoints */

    function signIn(callback as Lang.Method) as Lang.Boolean {
        switch (self.loginState) {
            case self.LOGIN_STATE_SIGNED_IN:
                return true;
            case self.LOGIN_STATE_SIGNED_OUT:
                self.pendingSyncTasks = [
                    new SyncTask(method(:getAuthorizationCode), null),
                ];
                self.startNextSyncTask(callback);
                return false;
            case self.LOGIN_STATE_PENDING_AUTH_CODE:
                self.pendingSyncTasks = [
                    new SyncTask(method(:getTokens), null),
                ];
                self.startNextSyncTask(callback);
                return false;
            default:
                return false;
        }
    }

    function signOut() {
        Storage.setValue("GOOGLE_CALENDAR_TOKENS", null);
        self.restoreTokens();
    }

    function sync(callback as Lang.Method) as Lang.Boolean {
        if (self.loginState != self.LOGIN_STATE_SIGNED_IN) {
            return false;
        }

        /* if token is too old, refresh */
        self.pendingSyncTasks = [
            new SyncTask(method(:syncRefreshTokens), null),
            new SyncTask(method(:syncCalendars), null),
            new SyncTask(method(:syncColors), null),
        ];
        self.startNextSyncTask(callback);
        return true;
    }

    function syncState() {
        self.restoreTokens();
        self.restoreData();
        return self;
    }

    function toggleSelectedCalendar(calendarId as Lang.String) {
        if (self.selectedCalendars.indexOf(calendarId) >= 0) {
            self.selectedCalendars.remove(calendarId);
        } else {
            self.selectedCalendars.add(calendarId);
        }
        self.storeData();
    }

    function getEvents() as Lang.Array<Lang.Dictionary> {
        return interleaveSortedSequences(
            self.events.values(),
            method(:_eventKey),
            method(:_eventFilter)
        );
    }

    function _eventKey(event as Lang.Dictionary) {
        return event["start"];
    }

    function _eventFilter(event as Lang.Dictionary) as Lang.Boolean {
        var includeAllDayEvents = Storage.getValue(
            "calendarIncludeAllDayEvents"
        );
        if (includeAllDayEvents == null) {
            includeAllDayEvents = false;
        }
        return includeAllDayEvents || event.get("allDay") == false;
    }

    /* State helpers */

    function restoreTokens() {
        var tokens = Storage.getValue("GOOGLE_CALENDAR_TOKENS");
        if (tokens instanceof Lang.Array) {
            tokens = tokens[0];
        }
        if (tokens == null) {
            tokens = {
                "login_state" => self.LOGIN_STATE_SIGNED_OUT,
                "refresh_token" => null,
                "access_token" => null,
                "access_token_expiry" => null,
                "device_code" => null,
                "user_code" => null,
                "user_code_expiry" => null,
            };
        }
        self.loginState = tokens.get("login_state");
        self.refreshToken = tokens.get("refresh_token");
        self.accessToken = tokens.get("access_token");
        self.accessTokenExpiry = tokens.get("access_token_expiry");
        self.deviceCode = tokens.get("device_code");
        self.userCode = tokens.get("user_code");
        self.userCodeExpiry = tokens.get("user_code_expiry");
    }

    function storeTokens() {
        Storage.setValue("GOOGLE_CALENDAR_TOKENS", {
            "login_state" => self.loginState,
            "refresh_token" => self.refreshToken,
            "access_token" => self.accessToken,
            "access_token_expiry" => self.accessTokenExpiry,
            "device_code" => self.deviceCode,
            "user_code" => self.userCode,
            "user_code_expiry" => self.userCodeExpiry,
        });
    }

    function restoreData() {
        self.calendars = Storage.getValue("GOOGLE_CALENDAR_CALENDARS");
        if (self.calendars == null) {
            self.calendars = {};
        }
        self.colors = Storage.getValue("GOOGLE_CALENDAR_COLORS");
        if (self.colors == null) {
            self.colors = {};
        }
        self.events = Storage.getValue("GOOGLE_CALENDAR_EVENTS");
        if (self.events == null) {
            self.events = {};
        }
        self.selectedCalendars = Storage.getValue(
            "GOOGLE_CALENDAR_CALENDARS_SELECTED"
        );
        if (self.selectedCalendars == null) {
            self.selectedCalendars = [];
        }
    }

    function storeData() {
        Storage.setValue("GOOGLE_CALENDAR_CALENDARS", self.calendars);
        Storage.setValue("GOOGLE_CALENDAR_COLORS", self.colors);
        Storage.setValue("GOOGLE_CALENDAR_EVENTS", self.events);
        Storage.setValue(
            "GOOGLE_CALENDAR_CALENDARS_SELECTED",
            self.selectedCalendars
        );
    }

    /* Sync tooling */

    function startNextSyncTask(callback as Lang.Method) as Void {
        if (pendingSyncTasks != null && pendingSyncTasks.size() > 0) {
            var nextTask = pendingSyncTasks[0];
            pendingSyncTasks.remove(nextTask);
            nextTask.start(callback);
            return;
        }
        self.storeData();
        callback.invoke(self.loginState);
    }

    /* Get authorization code */

    function getAuthorizationCode(
        params as Null,
        callback as Lang.Method
    ) as Void {
        Communications.makeWebRequest(
            "https://accounts.google.com/o/oauth2/device/code",
            {
                "client_id" => self.CLIENT_ID,
                "scope" => "https://www.googleapis.com/auth/calendar.readonly",
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :context => callback,
            },
            method(:onAuthorizationCode)
        );
        self.loginState = self.LOGIN_STATE_AWAITING_AUTH_CODE;
    }

    function onAuthorizationCode(responseCode, data, callback) {
        if (data != null) {
            deviceCode = data["device_code"];
            userCode = data["user_code"];
            userCodeExpiry = Time.now().value() + data["expires_in"];
            self.loginState = self.LOGIN_STATE_PENDING_AUTH_CODE;
        }
        self.storeTokens();
        self.startNextSyncTask(callback);
    }

    /* Retrieve auth tokens */

    function getTokens(params as Null, callback as Lang.Method) as Void {
        if (Time.now().value() > self.userCodeExpiry + 30) {
            pendingSyncTasks.add(
                new SyncTask(method(:getAuthorizationCode), null)
            );
            self.startNextSyncTask(callback);
            return;
        }

        Communications.makeWebRequest(
            "https://oauth2.googleapis.com/token",
            {
                "client_id" => self.CLIENT_ID,
                "client_secret" => self.CLIENT_SECRET,
                "device_code" => self.deviceCode,
                "grant_type" => "urn:ietf:params:oauth:grant-type:device_code",
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :context => callback,
            },
            method(:onGetTokens)
        );
    }

    function onGetTokens(responseCode as Lang.Number, data, callback) as Void {
        if (responseCode != 200) {
            return;
        }
        accessToken = data["access_token"];
        refreshToken = data["refresh_token"];
        accessTokenExpiry = Time.now().value() + data["expires_in"];
        // Deal with expiry data['expires_in'] (number of seconds)
        loginState = self.LOGIN_STATE_SIGNED_IN;
        self.storeTokens();
        self.sync(callback);
    }

    /* Refresh tokens during sync */

    function syncRefreshTokens(params, callback) {
        if (Time.now().value() < self.accessTokenExpiry + 60) {
            self.startNextSyncTask(callback);
            return;
        }

        Communications.makeWebRequest(
            "https://oauth2.googleapis.com/token",
            {
                "client_id" => self.CLIENT_ID,
                "client_secret" => self.CLIENT_SECRET,
                "grant_type" => "refresh_token",
                "refresh_token" => self.refreshToken,
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :context => callback,
            },
            method(:onRefreshTokens)
        );
    }

    function onRefreshTokens(responseCode, data, callback) {
        self.accessToken = data["access_token"];
        self.storeTokens();
        self.startNextSyncTask(callback);
    }

    /* Get calendars */

    function syncCalendars(params, callback) {
        Communications.makeWebRequest(
            "https://www.googleapis.com/calendar/v3/users/me/calendarList/",
            {
                "fields" => "items(id,summary,colorId,backgroundColor,primary)",
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Authorization" => "Bearer " + self.accessToken,
                },
                :context => callback,
            },
            method(:onCalendars)
        );
    }

    function onCalendars(responseCode, data, callback) {
        self.calendars = {};

        for (var i = 0; i < data["items"].size(); i++) {
            var calendarInfo = data["items"][i];
            calendars[calendarInfo["id"]] = {
                "id" => calendarInfo["id"],
                "name" => calendarInfo["summary"],
                "description" => calendarInfo["description"],
                "color" => calendarInfo["backgroundColor"]
                    .substring(1, null)
                    .toLongWithBase(16),
            };

            if (
                self.selectedCalendars.size() == 0 &&
                calendarInfo.get("primary") == true
            ) {
                self.selectedCalendars.add(calendarInfo["id"]);
            }

            if (selectedCalendars.indexOf(calendarInfo["id"]) >= 0) {
                pendingSyncTasks.add(
                    new SyncTask(method(:syncEvents), {
                        :calendar => calendarInfo["id"],
                        :calendarColor => calendarInfo["backgroundColor"],
                    })
                );
            }
        }

        self.startNextSyncTask(callback);
    }

    /* Get colors */

    function syncColors(params, callback) {
        Communications.makeWebRequest(
            "https://www.googleapis.com/calendar/v3/colors",
            {
                "fields" => "event",
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Authorization" => "Bearer " + self.accessToken,
                },
                :context => callback,
            },
            method(:onColors)
        );
    }

    function onColors(responseCode, data, callback) {
        self.colors = {};

        for (var i = 0; i < data["event"].size(); i++) {
            var colorId = data["event"].keys()[i];
            self.colors[colorId] = data["event"][colorId]["background"];
        }

        self.startNextSyncTask(callback);
    }

    /* Get events */

    function syncEvents(params as { :calendar as String }, callback) {
        var calendar = params[:calendar];

        var now = Time.now();
        var startTime = now.subtract(
            new Time.Duration(Gregorian.SECONDS_PER_HOUR * 2)
        );
        var endTime = now.add(
            new Time.Duration(Gregorian.SECONDS_PER_HOUR * 12)
        );

        Communications.makeWebRequest(
            "https://www.googleapis.com/calendar/v3/calendars/" +
                calendar +
                "/events",
            {
                "timeMin" => _convert_moment_to_isodate(startTime),
                "timeMax" => _convert_moment_to_isodate(endTime),
                "timeZone" => "UTC",
                "singleEvents" => "true",
                "orderBy" => "startTime",
                "fields"
                =>
                "items(start/date,start/dateTime,end/date,end/dateTime,summary,location)",
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Authorization" => "Bearer " + self.accessToken,
                },
                :context => {
                    :calendar => calendar,
                    :calendarColor => params[:calendarColor],
                    :callback => callback,
                },
            },
            method(:onGetEvents)
        );
    }

    function onGetEvents(
        responseCode,
        data,
        context as
            {
                :calendar as Lang.String,
                :calendarColor as Lang.String,
                :callback as Lang.Method,
            }
    ) as Void {
        if (data.hasKey("error")) {
            System.println("Error syncing events: " + data.toString());
            return;
        }
        if (events == null) {
            events = {};
        }
        events[context[:calendar]] = [];
        for (var i = 0; i < data["items"].size(); i++) {
            var eventInfo = data["items"][i];

            var eventColor = eventInfo.hasKey("colorId")
                ? self.colors.get(eventInfo["colorId"])
                : context[:calendarColor];
            events[context[:calendar]].add({
                "title" => eventInfo.get("summary"),
                "location" => eventInfo.get("location"),
                "color" => eventColor.substring(1, null).toLongWithBase(16),
                "start" => self._convert_datestr_to_timestamp(
                    eventInfo["start"].hasKey("dateTime")
                        ? eventInfo["start"]["dateTime"]
                        : eventInfo["start"]["date"]
                ),
                "end" => self._convert_datestr_to_timestamp(
                    eventInfo["end"].hasKey("dateTime")
                        ? eventInfo["end"]["dateTime"]
                        : eventInfo["end"]["date"]
                ),
                "allDay" => eventInfo["start"].hasKey("date"),
            });
        }

        self.storeData();

        self.startNextSyncTask(context[:callback]);
    }

    private function _convert_datestr_to_timestamp(
        dateStr as Lang.String
    ) as Lang.Number {
        if (dateStr.find("T") != null) {
            return Gregorian.moment({
                :year => dateStr.substring(0, 4).toNumber(),
                :month => dateStr.substring(5, 7).toNumber(),
                :day => dateStr.substring(8, 10).toNumber(),
                :hour => dateStr.substring(11, 13).toNumber(),
                :minute => dateStr.substring(14, 16).toNumber(),
                :second => dateStr.substring(17, 19).toNumber(),
            }).value();
        }
        var clockTime = System.getClockTime();
        var timezoneOffset = clockTime.timeZoneOffset;
        return (
            Gregorian.moment({
                :year => dateStr.substring(0, 4).toNumber(),
                :month => dateStr.substring(5, 7).toNumber(),
                :day => dateStr.substring(8, 10).toNumber(),
            }).value() - timezoneOffset
        );
    }

    private function _convert_moment_to_isodate(
        moment as Time.Moment
    ) as Lang.String {
        var info = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            info.year.format("%04u"),
            info.month.format("%02u"),
            info.day.format("%02u"),
            info.hour.format("%02u"),
            info.min.format("%02u"),
            info.sec.format("%02u"),
        ]);
    }
}

function interleaveSortedSequences(
    sequences as Array,
    keyCallback as Lang.Method,
    filterCallback as Lang.Method
) as Array {
    var out = [];
    var sequenceIndices = [];
    for (var i = 0; i < sequences.size(); i++) {
        sequenceIndices.add([0, sequences[i].size()]);
    }

    while (true) {
        var nextItem = null;
        var nextIndex = null;
        for (var i = 0; i < sequences.size(); i++) {
            var possibleItem = null;
            while (sequenceIndices[i][0] < sequenceIndices[i][1]) {
                possibleItem = sequences[i][sequenceIndices[i][0]];
                if (
                    filterCallback != null &&
                    !filterCallback.invoke(possibleItem)
                ) {
                    sequenceIndices[i][0] += 1;
                } else {
                    break;
                }
            }
            if (
                nextItem == null ||
                (possibleItem != null &&
                    keyCallback.invoke(nextItem) >
                        keyCallback.invoke(possibleItem))
            ) {
                nextItem = possibleItem;
                nextIndex = i;
            }
        }
        if (nextItem == null) {
            break;
        }
        out.add(nextItem);
        sequenceIndices[nextIndex][0] += 1;
    }

    return out;
}
