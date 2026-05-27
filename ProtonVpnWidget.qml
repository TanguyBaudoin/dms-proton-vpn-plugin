import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    pluginId: "protonVPNplugin"
    layerNamespacePlugin: "proton-vpn"

    property string locationInputText: ""
    property string locationsSearchText: ""
    property string citySearchText: ""
    property string dnsInputText: ""
    property bool dnsInputFocused: false
    property bool showLocationInBar: pluginData.showLocationInBar !== undefined ? pluginData.showLocationInBar : true

    readonly property bool commandsAvailable: VpnService.cliAvailable && !VpnService.commandRunning
    readonly property color heroAccent: !VpnService.cliAvailable ? Theme.warning : (VpnService.isConnected ? Theme.primary : Theme.surfaceText)

    readonly property var filteredLocations: {
        const source = VpnService.locations || [];
        const favorites = [];
        const others = [];

        for (let i = 0; i < source.length; i++) {
            const item = source[i] || {};
            if (VpnService.isFavoriteLocation(item.iso)) {
                favorites.push(item);
            } else {
                others.push(item);
            }
        }

        const sortedSource = favorites.concat(others);
        const query = (root.locationsSearchText || "").toString().trim().toLowerCase();
        if (!query) {
            return sortedSource;
        }

        const filtered = [];
        for (let i = 0; i < sortedSource.length; i++) {
            const item = sortedSource[i] || {};
            const iso = (item.iso || "").toString().toLowerCase();
            const city = (item.city || "").toString().toLowerCase();
            const country = (item.country || "").toString().toLowerCase();
            const label = `${city}, ${country} (${iso})`;

            if (iso.indexOf(query) >= 0 || city.indexOf(query) >= 0 || country.indexOf(query) >= 0 || label.indexOf(query) >= 0) {
                filtered.push(item);
            }
        }
        return filtered;
    }

    readonly property var filteredCities: {
        const source = VpnService.currentCities || [];
        const query = (root.citySearchText || "").toString().trim().toLowerCase();
        if (!query) {
            return source;
        }

        const filtered = [];
        for (let i = 0; i < source.length; i++) {
            const item = source[i] || {};
            const name = (item.name || "").toString().toLowerCase();
            const features = (item.featuresText || "").toString().toLowerCase();
            if (name.indexOf(query) >= 0 || features.indexOf(query) >= 0) {
                filtered.push(item);
            }
        }

        return filtered;
    }

    function t(key, fallback, params) {
        return VpnI18n.tr(key, fallback, params);
    }

    readonly property string barIconName: {
        if (!VpnService.cliAvailable) {
            return "warning";
        }
        if (VpnService.commandRunning) {
            return "sync";
        }
        return VpnService.isConnected ? "shield_lock" : "shield";
    }

    readonly property color barIconColor: {
        if (!VpnService.cliAvailable) {
            return Theme.warning;
        }
        if (VpnService.isConnected) {
            return Theme.primary;
        }
        return Theme.surfaceVariantText;
    }

    readonly property string barText: {
        if (!VpnService.cliAvailable) {
            return root.t("bar.cli", "CLI");
        }
        if (VpnService.commandRunning) {
            return root.t("bar.pending", "...");
        }
        if (VpnService.isConnected) {
            return VpnService.connectedLocation || root.t("bar.connected_short", "Connected");
        }
        return root.t("bar.off", "Off");
    }

    readonly property string heroTitle: {
        if (!VpnService.cliAvailable) {
            return root.t("status.cli_unavailable", "protonvpn unavailable");
        }
        if (VpnService.isConnected) {
            return root.t("summary.connected_to", "Connected to {location}", {
                location: root.safeText(VpnService.connectedLocation, root.t("summary.location_unknown", "location unknown"))
            });
        }
        return root.safeText(VpnService.statusSummary, root.t("status.disconnected", "Disconnected"));
    }

    readonly property string heroSupportingText: {
        if (VpnService.lastError) {
            return VpnService.lastError;
        }
        if (!VpnService.cliAvailable) {
            return root.t("hero.unavailable_hint", "Check the CLI path and session state in settings.");
        }
        if (VpnService.commandRunning) {
            return root.t("status.running_command", "Running: {command}", {
                command: VpnService.runningCommand
            });
        }
        return root.t("hero.offline_hint", "Ready to secure traffic, switch regions, and tune transport behavior.");
    }

    function formatTimestamp(ms) {
        if (!ms || ms <= 0) {
            return root.t("time.never", "never");
        }

        try {
            return new Date(ms).toLocaleTimeString();
        } catch (error) {
            return root.t("time.unknown", "unknown");
        }
    }

    function safeText(value, fallback) {
        if (value === undefined || value === null || value === "") {
            return fallback;
        }
        return value;
    }

    component VpnActionButton: StyledRect {
        id: buttonRoot

        required property string iconName
        required property string label
        property string description: ""
        property bool active: false
        property bool actionEnabled: true
        property bool prominent: false
        property bool compact: false
        readonly property bool emphasized: active || prominent
        readonly property bool showLeadingIcon: iconName.length > 0 && (!compact || width >= 104)

        signal triggered

        implicitHeight: {
            if (compact) {
                return 40;
            }
            if (description.length > 0) {
                return 58;
            }
            return prominent ? 50 : 46;
        }
        radius: Theme.cornerRadius
        color: {
            if (!actionEnabled) {
                return Theme.surfaceContainer;
            }
            if (emphasized) {
                return Theme.primaryContainer;
            }
            return buttonMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer;
        }
        border.width: 1
        border.color: {
            if (buttonRoot.activeFocus) {
                return Theme.primary;
            }
            if (emphasized) {
                return Theme.withAlpha(Theme.primary, 0.42);
            }
            return buttonMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.18) : Theme.outlineVariant;
        }
        opacity: actionEnabled ? 1 : 0.52
        scale: actionEnabled && buttonMouse.containsMouse ? 1.01 : 1.0
        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 140
            }
        }

        RowLayout {
            id: actionRow
            anchors.fill: parent
            anchors.leftMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.rightMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.topMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.bottomMargin: compact ? Theme.spacingS : Theme.spacingM
            spacing: compact ? Theme.spacingXS : Theme.spacingS

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: buttonRoot.showLeadingIcon
                width: compact ? 24 : 28
                height: compact ? 24 : 28
                radius: width / 2
                color: buttonRoot.emphasized ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceText, 0.08)

                DankIcon {
                    anchors.centerIn: parent
                    name: buttonRoot.iconName
                    size: compact ? 14 : 16
                    color: buttonRoot.emphasized ? Theme.primary : Theme.surfaceText
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: compact ? 0 : 2

                StyledText {
                    width: parent.width
                    text: buttonRoot.label
                    font.pixelSize: compact ? Theme.fontSizeSmall - 1 : Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: buttonRoot.emphasized ? Theme.primary : Theme.surfaceText
                    horizontalAlignment: buttonRoot.showLeadingIcon ? Text.AlignLeft : Text.AlignHCenter
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                StyledText {
                    visible: !compact && buttonRoot.description.length > 0
                    width: parent.width
                    text: buttonRoot.description
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: buttonRoot.actionEnabled
            hoverEnabled: true
            cursorShape: buttonRoot.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: buttonRoot.triggered()
        }
    }

    component EmptyStateCard: Rectangle {
        id: emptyRoot

        required property string title
        required property string body
        property string actionLabel: ""
        property string actionIcon: "refresh"
        property bool actionEnabled: true

        signal actionTriggered

        width: parent ? parent.width : implicitWidth
        implicitHeight: emptyColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)

        Column {
            id: emptyColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: Theme.withAlpha(root.heroAccent, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(root.heroAccent, 0.22)

                DankIcon {
                    anchors.centerIn: parent
                    name: emptyRoot.actionIcon
                    size: 18
                    color: root.heroAccent
                }
            }

            StyledText {
                width: parent.width
                text: emptyRoot.title
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: emptyRoot.body
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            VpnActionButton {
                visible: emptyRoot.actionLabel.length > 0
                width: Math.min(parent.width, 180)
                iconName: emptyRoot.actionIcon
                label: emptyRoot.actionLabel
                compact: true
                actionEnabled: emptyRoot.actionEnabled
                onTriggered: emptyRoot.actionTriggered()
            }
        }
    }

    component TagChip: Rectangle {
        id: chipRoot

        required property string text
        property color toneColor: Theme.primary
        property bool strong: false

        implicitWidth: chipLabel.implicitWidth + Theme.spacingM * 2
        implicitHeight: 28
        radius: 14
        color: strong ? Theme.withAlpha(toneColor, 0.18) : Theme.withAlpha(Theme.surfaceContainerHighest, 0.68)
        border.width: 1
        border.color: strong ? Theme.withAlpha(toneColor, 0.35) : Theme.outlineVariant

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: chipRoot.text
            color: chipRoot.strong ? chipRoot.toneColor : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall - 1
            font.weight: chipRoot.strong ? Font.DemiBold : Font.Medium
        }
    }

    component MetricTile: Rectangle {
        id: tileRoot

        required property string label
        required property string value
        property color accentColor: Theme.primary

        implicitHeight: tileColumn.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.4)
        border.width: 1
        border.color: Theme.withAlpha(tileRoot.accentColor, 0.18)

        Column {
            id: tileColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: 4

            StyledText {
                width: parent.width
                text: tileRoot.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tileRoot.value
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    component SectionFrame: StyledRect {
        id: sectionRoot

        required property string title
        property string subtitle: ""
        property string aside: ""
        default property alias contentData: sectionBody.data

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 2
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.outlineVariant
        implicitHeight: sectionColumn.implicitHeight + Theme.spacingL * 2

        Column {
            id: sectionColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        width: parent.width
                        text: sectionRoot.title
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: sectionRoot.subtitle.length > 0
                        width: parent.width
                        text: sectionRoot.subtitle
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                    }
                }

                TagChip {
                    visible: sectionRoot.aside.length > 0
                    text: sectionRoot.aside
                    toneColor: root.heroAccent
                    strong: false
                }
            }

            Column {
                id: sectionBody
                width: parent.width
                spacing: Theme.spacingM
            }
        }
    }

    component ConfigGroup: Rectangle {
        id: groupRoot

        required property string title
        default property alias contentData: groupBody.data

        implicitHeight: groupColumn.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)

        Column {
            id: groupColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: groupRoot.title
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
            }

            Column {
                id: groupBody
                width: parent.width
                spacing: Theme.spacingS
            }
        }
    }

    Connections {
        target: pluginService

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== root.pluginId) {
                return;
            }

            locationInputText = pluginData.defaultLocation || "";
            locationsSearchText = locationInputText;
        }
    }

    Connections {
        target: VpnService

        function onDnsUpstreamChanged() {
            if (!root.dnsInputFocused) {
                dnsInputText = VpnService.dnsUpstream || "";
            }
        }

        function onSelectedCountryIsoChanged() {
            root.citySearchText = "";
        }
    }

    Component.onCompleted: {
        locationInputText = pluginData.defaultLocation || "";
        locationsSearchText = locationInputText;
        dnsInputText = VpnService.dnsUpstream || "";
        VpnService.refreshAll(true);
    }

    popoutWidth: 520
    popoutHeight: 760

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.barIconName
                size: root.iconSize
                color: root.barIconColor
                anchors.verticalCenter: parent.verticalCenter

                RotationAnimator on rotation {
                    running: VpnService.commandRunning
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: 1100
                }
            }

            StyledText {
                visible: root.showLocationInBar
                text: root.barText
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                width: 140
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.barIconName
                size: root.iconSize
                color: root.barIconColor
                anchors.horizontalCenter: parent.horizontalCenter

                RotationAnimator on rotation {
                    running: VpnService.commandRunning
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: 1100
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: root.t("app.title", "Proton VPN")
            detailsText: VpnService.cliAvailable ? VpnService.statusSummary : root.t("popout.details.cli_unavailable", "protonvpn not available")
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    clip: true
                    contentWidth: width - Theme.spacingM * 2
                    contentHeight: contentColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        anchors.right: parent.right
                        anchors.rightMargin: -Theme.spacingM
                    }

                    Column {
                        id: contentColumn
                        width: contentFlick.width
                        spacing: Theme.spacingM

                        StyledRect {
                            width: parent.width
                            radius: Theme.cornerRadius + 6
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, VpnService.isConnected ? 0.34 : 0.18)
                            implicitHeight: heroColumn.implicitHeight + Theme.spacingL * 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Theme.withAlpha(root.heroAccent, VpnService.isConnected ? 0.16 : 0.07)
                                    }
                                    GradientStop {
                                        position: 0.55
                                        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.08)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: Theme.withAlpha(Theme.surfaceContainer, 0.02)
                                    }
                                }
                            }

                            Rectangle {
                                width: 180
                                height: 180
                                radius: 90
                                x: parent.width - width * 0.72
                                y: -height * 0.35
                                color: Theme.withAlpha(root.heroAccent, 0.08)
                            }

                            Rectangle {
                                width: 140
                                height: 140
                                radius: 70
                                x: -width * 0.25
                                y: parent.height - height * 0.55
                                color: Theme.withAlpha(Theme.surfaceText, 0.04)
                            }

                            Column {
                                id: heroColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingL
                                spacing: Theme.spacingM

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Rectangle {
                                        width: 44
                                        height: 44
                                        radius: 22
                                        color: Theme.withAlpha(root.heroAccent, 0.18)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.28)

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: root.barIconName
                                            size: 22
                                            color: root.heroAccent

                                            RotationAnimator on rotation {
                                                running: VpnService.commandRunning
                                                from: 0
                                                to: 360
                                                loops: Animation.Infinite
                                                duration: 1100
                                            }
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            width: parent.width
                                            text: root.t("hero.eyebrow", "Tunnel control")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: root.heroTitle
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeLarge + 4
                                            font.weight: Font.Bold
                                            wrapMode: Text.WordWrap
                                        }
                                    }

                                    TagChip {
                                        text: root.barText
                                        toneColor: root.heroAccent
                                        strong: VpnService.isConnected || !VpnService.cliAvailable
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.heroSupportingText
                                    color: VpnService.lastError ? Theme.warning : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    TagChip {
                                        text: root.t("summary.plan_devices", "Plan: {plan}  •  Devices: {devices}", {
                                            plan: root.safeText(VpnService.accountTier, root.t("time.unknown", "unknown")),
                                            devices: (VpnService.maxDevices || "-")
                                        })
                                        toneColor: root.heroAccent
                                        strong: VpnService.isConnected
                                    }

                                    TagChip {
                                        visible: !!VpnService.subscriptionRenewDate
                                        text: root.t("summary.renewal", "Renewal: {date}", {
                                            date: VpnService.subscriptionRenewDate
                                        })
                                        toneColor: root.heroAccent
                                    }

                                    TagChip {
                                        text: `${root.t("config.mode", "Mode")}: ${root.safeText(VpnService.currentMode, "-")}`
                                        toneColor: root.heroAccent
                                    }

                                    TagChip {
                                        text: `${root.t("config.protocol", "Protocol")}: ${root.safeText(VpnService.currentProtocolRaw || VpnService.currentProtocol, "-")}`
                                        toneColor: root.heroAccent
                                    }

                                    TagChip {
                                        text: `${root.t("config.update_channel", "Update channel")}: ${root.safeText(VpnService.currentUpdateChannel, "-")}`
                                        toneColor: root.heroAccent
                                    }
                                }

                                GridLayout {
                                    width: parent.width
                                    columns: 2
                                    columnSpacing: Theme.spacingS
                                    rowSpacing: Theme.spacingS

                                    MetricTile {
                                        Layout.fillWidth: true
                                        label: root.t("meta.account", "Account")
                                        value: root.safeText(VpnService.accountEmail, root.t("summary.not_logged", "not logged"))
                                        accentColor: root.heroAccent
                                    }

                                    MetricTile {
                                        Layout.fillWidth: true
                                        label: root.t("meta.last_sync", "Last sync")
                                        value: root.formatTimestamp(VpnService.lastRefreshMs)
                                        accentColor: root.heroAccent
                                    }

                                    MetricTile {
                                        Layout.fillWidth: true
                                        label: root.t("meta.last_command", "Last command")
                                        value: VpnService.lastCommandText ? `${VpnService.lastCommandText} (${VpnService.lastCommandExitCode})` : root.t("meta.none", "None")
                                        accentColor: root.heroAccent
                                    }

                                    MetricTile {
                                        Layout.fillWidth: true
                                        label: root.t("meta.default_location", "Default location")
                                        value: root.safeText(pluginData.defaultLocation, root.t("meta.not_set", "Not set"))
                                        accentColor: root.heroAccent
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    VpnActionButton {
                                        width: parent.width
                                        iconName: VpnService.isConnected ? "link_off" : "link"
                                        label: VpnService.isConnected ? root.t("action.disconnect", "Disconnect") : root.t("action.connect", "Connect")
                                        description: VpnService.isConnected ? root.t("hero.disconnect_description", "Drop the current tunnel and keep the control surface ready.") : root.t("hero.connect_description", "Start the VPN using your preferred strategy and current runtime settings.")
                                        prominent: true
                                        active: VpnService.isConnected
                                        actionEnabled: root.commandsAvailable
                                        onTriggered: VpnService.toggleConnection()
                                    }

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "speed"
                                            label: root.t("action.fastest", "Fastest")
                                            compact: true
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.connectFastest()
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "refresh"
                                            label: root.t("action.refresh", "Refresh")
                                            compact: true
                                            actionEnabled: !VpnService.commandRunning
                                            onTriggered: VpnService.refreshAll(true)
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "article"
                                            label: root.t("action.open_log", "Open Log")
                                            compact: true
                                            actionEnabled: !VpnService.commandRunning
                                            onTriggered: {
                                                ToastService.showInfo(root.t("app.title", "Proton VPN"), root.t("toast.log_opening", "Opening tunnel log..."));
                                                VpnService.openTunnelLog();
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: !!VpnService.lastCommandOutput
                                    width: parent.width
                                    implicitHeight: outputColumn.implicitHeight + Theme.spacingM * 2
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.46)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.08)

                                    Column {
                                        id: outputColumn
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: 4

                                        StyledText {
                                            width: parent.width
                                            text: root.t("hero.command_output", "Command output")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: VpnService.lastCommandOutput
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 4
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        SectionFrame {
                            title: root.t("section.locations", "Locations")
                            subtitle: root.t("locations.section_subtitle", "Search the ranked list, jump straight to a region, or save a default route.")
                            aside: `${root.filteredLocations.length}/${VpnService.locations.length || 0}`

                            Column {
                                width: parent.width
                                spacing: Theme.spacingS

                                Column {
                                    width: parent.width
                                    spacing: 4

                                    StyledText {
                                        width: parent.width
                                        text: root.t("locations.search_destination_label", "Search destination")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    Item {
                                        width: parent.width
                                        implicitHeight: 42

                                        DankIcon {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "search"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                        }

                                        TextField {
                                            id: locationsSearchInput
                                            anchors.fill: parent
                                            placeholderText: activeFocus ? "" : root.t("locations.placeholder", "City, country, or ISO code (e.g. Sao Paulo / BR)")
                                            placeholderTextColor: Theme.surfaceVariantText
                                            leftPadding: Theme.spacingXL
                                            rightPadding: Theme.spacingM
                                            topPadding: Theme.spacingS
                                            bottomPadding: Theme.spacingS
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.locationsSearchText
                                            selectByMouse: true
                                            color: Theme.surfaceText
                                            selectedTextColor: Theme.onPrimary
                                            selectionColor: Theme.primary
                                            onTextChanged: {
                                                root.locationsSearchText = text;
                                                root.locationInputText = text;
                                            }

                                            background: Rectangle {
                                                radius: Theme.cornerRadius
                                                color: Theme.surfaceContainer
                                                border.width: 1
                                                border.color: locationsSearchInput.activeFocus ? Theme.primary : Theme.outlineVariant
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    VpnActionButton {
                                        Layout.fillWidth: true
                                        iconName: "near_me"
                                        label: root.t("action.connect", "Connect")
                                        compact: true
                                        actionEnabled: root.commandsAvailable && locationsSearchInput.text.trim().length > 0
                                        onTriggered: {
                                            const destination = locationsSearchInput.text.trim();
                                            if (!destination) {
                                                return;
                                            }
                                            VpnService.connectToLocation(destination);
                                        }
                                    }

                                    VpnActionButton {
                                        Layout.fillWidth: true
                                        iconName: "public"
                                        label: root.t("action.connect_country", "Connect Country")
                                        compact: true
                                        actionEnabled: root.commandsAvailable && !!VpnService.selectedCountryIso
                                        onTriggered: VpnService.connectToCountry(VpnService.selectedCountryIso)
                                    }

                                    VpnActionButton {
                                        Layout.fillWidth: true
                                        iconName: "save"
                                        label: root.t("action.set_default", "Set Default")
                                        compact: true
                                        actionEnabled: locationsSearchInput.text.trim().length > 0
                                        onTriggered: {
                                            const value = locationsSearchInput.text.trim();
                                            root.locationInputText = value;
                                            VpnService.saveSetting("defaultLocation", value);
                                            ToastService.showInfo(root.t("app.title", "Proton VPN"), root.t("toast.default_location_saved", "Default location saved: {location}", {
                                                location: value
                                            }));
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.t("locations.filtered_count", "Showing {shown}/{total} • Last update: {time}", {
                                            shown: root.filteredLocations.length,
                                            total: VpnService.locations.length,
                                            time: root.formatTimestamp(VpnService.lastLocationsRefreshMs)
                                        })
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        visible: !!pluginData.defaultLocation
                                        text: root.t("locations.saved_default", "Saved default: {value}", {
                                            value: pluginData.defaultLocation
                                        })
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                StyledText {
                                    visible: root.locationsSearchText.trim().length > 0 && root.filteredLocations.length === 0
                                    width: parent.width
                                    text: root.t("locations.no_matches", "No locations match this search")
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                EmptyStateCard {
                                    visible: !VpnService.commandRunning && root.locationsSearchText.trim().length === 0 && root.filteredLocations.length === 0
                                    title: root.t("locations.empty_title", "No ranked locations yet")
                                    body: root.t("locations.empty_body", "Fetch the latest list from the CLI to unlock quick-connect suggestions and favorites.")
                                    actionLabel: root.t("action.refresh", "Refresh")
                                    actionIcon: "refresh"
                                    actionEnabled: !VpnService.commandRunning
                                    onActionTriggered: VpnService.refreshAll(true)
                                }

                                Rectangle {
                                    visible: root.filteredLocations.length > 0
                                    width: parent.width
                                    height: Math.min(locationList.contentHeight, (8 * 68) + (7 * Theme.spacingS))
                                    radius: Theme.cornerRadius
                                    color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.35)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
                                    clip: true

                                    ListView {
                                        id: locationList
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingXS
                                        clip: true
                                        spacing: Theme.spacingS
                                        model: root.filteredLocations
                                        boundsBehavior: Flickable.StopAtBounds
                                        ScrollBar.vertical: ScrollBar {}

                                        delegate: StyledRect {
                                            id: locationCard

                                            required property var modelData
                                            readonly property var locationItem: modelData
                                            readonly property bool favorite: VpnService.isFavoriteLocation(locationItem.iso)
                                            readonly property bool selected: (VpnService.selectedCountryIso || "").toUpperCase() === (locationItem.iso || "")

                                            width: ListView.view.width
                                            implicitHeight: locationRow.implicitHeight + Theme.spacingM * 2
                                            radius: Theme.cornerRadius
                                            color: locationMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                                            border.width: 1
                                            border.color: locationCard.selected ? Theme.withAlpha(Theme.primary, 0.5) : (locationCard.favorite ? Theme.withAlpha(Theme.primary, 0.28) : Theme.withAlpha(Theme.surfaceText, 0.08))
                                            scale: locationMouse.containsMouse ? 1.004 : 1.0

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 140
                                                }
                                            }

                                            Behavior on border.color {
                                                ColorAnimation {
                                                    duration: 140
                                                }
                                            }

                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 140
                                                }
                                            }

                                            MouseArea {
                                                id: locationMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: VpnService.selectCountry(locationCard.locationItem.iso, locationCard.locationItem.country)
                                            }

                                            RowLayout {
                                                id: locationRow
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.spacingM
                                                anchors.rightMargin: Theme.spacingM
                                                spacing: Theme.spacingM

                                                Rectangle {
                                                    width: 40
                                                    height: 28
                                                    radius: 14
                                                    color: Theme.withAlpha(Theme.primary, 0.14)
                                                    border.width: 1
                                                    border.color: Theme.withAlpha(Theme.primary, 0.22)

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: locationCard.locationItem.iso
                                                        color: Theme.primary
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.Bold
                                                    }
                                                }

                                                Column {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    StyledText {
                                                        width: parent.width
                                                        text: `${locationCard.locationItem.city}, ${locationCard.locationItem.country}`
                                                        color: Theme.surfaceText
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    StyledText {
                                                        width: parent.width
                                                        text: locationCard.selected ? root.t("locations.country_selected_hint", "Country selected. Cities loaded below.") : root.t("locations.row_select_hint", "Tap to select this country")
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: pingLabel.implicitWidth + Theme.spacingM * 2
                                                    height: 28
                                                    radius: 14
                                                    color: Theme.withAlpha(Theme.surfaceText, 0.06)
                                                    border.width: 1
                                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.08)

                                                    StyledText {
                                                        id: pingLabel
                                                        anchors.centerIn: parent
                                                        text: locationCard.locationItem.ping >= 0 ? `${locationCard.locationItem.ping}ms` : "-"
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        font.weight: Font.Medium
                                                    }
                                                }

                                                Rectangle {
                                                    width: 30
                                                    height: 30
                                                    radius: 15
                                                    color: favoriteMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.surfaceText, 0.06)
                                                    border.width: 1
                                                    border.color: locationCard.favorite ? Theme.withAlpha(Theme.primary, 0.28) : Theme.withAlpha(Theme.surfaceText, 0.08)
                                                    z: 2

                                                    DankIcon {
                                                        anchors.centerIn: parent
                                                        name: locationCard.favorite ? "star" : "star_border"
                                                        size: 16
                                                        color: locationCard.favorite ? Theme.primary : Theme.surfaceVariantText
                                                    }

                                                    MouseArea {
                                                        id: favoriteMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: VpnService.toggleFavoriteLocation(locationCard.locationItem.iso)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Column {
                                    visible: !!VpnService.selectedCountryIso
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.t("locations.cities_title", "Cities in {country} ({iso})", {
                                                country: VpnService.selectedCountryName || "-",
                                                iso: VpnService.selectedCountryIso || "--"
                                            })
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }

                                        VpnActionButton {
                                            Layout.preferredWidth: 120
                                            iconName: "refresh"
                                            label: root.t("action.refresh", "Refresh")
                                            compact: true
                                            actionEnabled: !VpnService.citiesLoading
                                            onTriggered: VpnService.refreshCitiesForCountry(VpnService.selectedCountryIso, true)
                                        }
                                    }

                                    Item {
                                        width: parent.width
                                        implicitHeight: 42

                                        DankIcon {
                                            anchors.left: parent.left
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "location_city"
                                            size: 16
                                            color: Theme.surfaceVariantText
                                        }

                                        TextField {
                                            id: citySearchInput
                                            anchors.fill: parent
                                            placeholderText: activeFocus ? "" : root.t("locations.cities_search_placeholder", "Search city")
                                            placeholderTextColor: Theme.surfaceVariantText
                                            leftPadding: Theme.spacingXL
                                            rightPadding: Theme.spacingM
                                            topPadding: Theme.spacingS
                                            bottomPadding: Theme.spacingS
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.citySearchText
                                            selectByMouse: true
                                            color: Theme.surfaceText
                                            selectedTextColor: Theme.onPrimary
                                            selectionColor: Theme.primary
                                            onTextChanged: root.citySearchText = text

                                            background: Rectangle {
                                                radius: Theme.cornerRadius
                                                color: Theme.surfaceContainer
                                                border.width: 1
                                                border.color: citySearchInput.activeFocus ? Theme.primary : Theme.outlineVariant
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: VpnService.citiesLoading
                                        width: parent.width
                                        text: root.t("locations.cities_loading", "Loading cities...")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }

                                    StyledText {
                                        visible: !VpnService.citiesLoading && root.filteredCities.length === 0
                                        width: parent.width
                                        text: root.t("locations.cities_empty", "No cities available for this country")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.WordWrap
                                    }

                                    Rectangle {
                                        visible: root.filteredCities.length > 0
                                        width: parent.width
                                        height: Math.min(cityList.contentHeight, (6 * 64) + (5 * Theme.spacingS))
                                        radius: Theme.cornerRadius
                                        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.35)
                                        border.width: 1
                                        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
                                        clip: true

                                        ListView {
                                            id: cityList
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingXS
                                            clip: true
                                            spacing: Theme.spacingS
                                            model: root.filteredCities
                                            boundsBehavior: Flickable.StopAtBounds
                                            ScrollBar.vertical: ScrollBar {}

                                            delegate: StyledRect {
                                                required property var modelData
                                                readonly property var cityItem: modelData

                                                width: ListView.view.width
                                                implicitHeight: cityColumn.implicitHeight + Theme.spacingM * 2
                                                radius: Theme.cornerRadius
                                                color: cityMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                                                border.width: 1
                                                border.color: Theme.withAlpha(Theme.surfaceText, 0.08)

                                                MouseArea {
                                                    id: cityMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: VpnService.connectToCity(cityItem.name)
                                                }

                                                Column {
                                                    id: cityColumn
                                                    anchors.fill: parent
                                                    anchors.margins: Theme.spacingM
                                                    spacing: 2

                                                    StyledText {
                                                        width: parent.width
                                                        text: cityItem.name || ""
                                                        color: Theme.surfaceText
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    StyledText {
                                                        visible: !!cityItem.featuresText
                                                        width: parent.width
                                                        text: cityItem.featuresText
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                        elide: Text.ElideRight
                                                    }

                                                    StyledText {
                                                        width: parent.width
                                                        text: root.t("locations.cities_row_hint", "Tap to connect to this city")
                                                        color: Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall - 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionFrame {
                            title: root.t("section.configuration", "Configuration")
                            subtitle: root.t("config.section_subtitle", "Tune transport, release stream, and resolver without leaving the control surface.")

                            GridLayout {
                                width: parent.width
                                columns: 2
                                columnSpacing: Theme.spacingS
                                rowSpacing: Theme.spacingS

                                ConfigGroup {
                                    Layout.fillWidth: true
                                    title: root.t("config.mode", "Mode")

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "device_hub"
                                            label: "STANDARD"
                                            compact: true
                                            active: (VpnService.currentMode || "").toLowerCase() === "standard"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setMode("tun")
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "safety_check"
                                            label: "OFF"
                                            compact: true
                                            active: (VpnService.currentMode || "").toLowerCase() === "off"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setMode("socks")
                                        }
                                    }
                                }

                                ConfigGroup {
                                    Layout.fillWidth: true
                                    title: root.t("config.protocol", "Protocol")

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "auto_awesome"
                                            label: "OFF"
                                            compact: true
                                            active: VpnService.currentProtocol === "auto"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setProtocol("auto")
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "http"
                                            label: "MALWARE"
                                            compact: true
                                            active: VpnService.currentProtocol === "http2"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setProtocol("http2")
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "rocket_launch"
                                            label: "FULL"
                                            compact: true
                                            active: VpnService.currentProtocol === "quic"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setProtocol("quic")
                                        }
                                    }
                                }

                                ConfigGroup {
                                    Layout.fillWidth: true
                                    Layout.columnSpan: 2
                                    title: root.t("config.update_channel", "Update channel")

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "new_releases"
                                            label: root.t("action.release", "Release")
                                            compact: true
                                            active: VpnService.currentUpdateChannel === "release"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setUpdateChannel("release")
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "science"
                                            label: root.t("action.beta", "Beta")
                                            compact: true
                                            active: VpnService.currentUpdateChannel === "beta"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setUpdateChannel("beta")
                                        }

                                        VpnActionButton {
                                            Layout.fillWidth: true
                                            iconName: "bolt"
                                            label: root.t("action.nightly", "Nightly")
                                            compact: true
                                            active: VpnService.currentUpdateChannel === "nightly"
                                            actionEnabled: root.commandsAvailable
                                            onTriggered: VpnService.setUpdateChannel("nightly")
                                        }
                                    }
                                }

                                ConfigGroup {
                                    Layout.fillWidth: true
                                    Layout.columnSpan: 2
                                    title: root.t("config.dns_upstream", "DNS upstream")

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        DankTextField {
                                            id: dnsInput
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            Layout.preferredWidth: 1
                                            placeholderText: root.t("config.dns_placeholder", "1.1.1.1, tls://dns.dns.example, https://dns.example/dns-query")
                                            backgroundColor: Theme.surfaceContainer
                                            normalBorderColor: Theme.outlineVariant
                                            focusedBorderColor: Theme.primary
                                            height: 42
                                            text: root.dnsInputText
                                            onTextChanged: root.dnsInputText = text
                                            onFocusStateChanged: hasFocus => root.dnsInputFocused = hasFocus
                                        }

                                        VpnActionButton {
                                            Layout.preferredWidth: 132
                                            Layout.minimumWidth: 132
                                            iconName: "check"
                                            label: root.t("action.apply", "Apply")
                                            compact: true
                                            actionEnabled: root.commandsAvailable && dnsInput.text.trim().length > 0
                                            onTriggered: VpnService.setDns(dnsInput.text.trim())
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: Theme.spacingL
                        }
                    }
                }
            }
        }
    }
}
