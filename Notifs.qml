pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Notification daemon. Owns org.freedesktop.Notifications and feeds the island one
// notification at a time (the rest wait in a queue).
Singleton {
    id: root

    property var current: null   // notification shown in the island right now
    property var queue: []       // waiting behind it

    function show(n) {
        if (root.current === null) root.current = n;
        else root.queue = root.queue.concat([n]);
    }

    // Move on to the next waiting notification (the current one stays tracked/unread).
    function next() {
        const q = root.queue.slice();
        root.current = q.length > 0 ? q.shift() : null;
        root.queue = q;
    }

    // Invoke the default action (if any) and move on.
    function activate() {
        const n = root.current;
        if (!n) return;
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        root.next();
    }

    // If the sender closes the notification we're showing, move on.
    Connections {
        target: root.current
        function onClosed() { root.next(); }
    }

    NotificationServer {
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true

        onNotification: n => {
            n.tracked = true;
            root.show(n);
        }
    }
}
