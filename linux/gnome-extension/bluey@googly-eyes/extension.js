// Bluey overlay for GNOME Shell (Wayland): the parts only the compositor may do.
// The Python host drives it over D-Bus (name co.visionairy.Bluey.Overlay). It draws, reports the pointer and
// focused app, warps the pointer for clicks, and forwards menu choices and hotkeys as Action signals.
// It never clicks, types or captures the screen itself.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `<node><interface name="co.visionairy.Bluey.Overlay">
  <method name="GetState"><arg type="d" direction="out"/><arg type="d" direction="out"/>
    <arg type="d" direction="out"/><arg type="d" direction="out"/><arg type="s" direction="out"/></method>
  <method name="Warp"><arg type="d" direction="in"/><arg type="d" direction="in"/></method>
  <method name="SetCursor"><arg type="b" direction="in"/><arg type="d" direction="in"/><arg type="d" direction="in"/>
    <arg type="d" direction="out"/></method>
  <method name="SetCaption"><arg type="s" direction="in"/></method>
  <method name="Flash"><arg type="s" direction="in"/></method>
  <method name="SetCountdown"><arg type="s" direction="in"/></method>
  <method name="SetHidden"><arg type="b" direction="in"/></method>
  <method name="SetMenu"><arg type="s" direction="in"/></method>
  <signal name="Action"><arg type="s"/></signal>
</interface></node>`;

const KEYS = {'stop': 'stop', 'toggle-awake': 'toggleAwake', 'point-here': 'pointHere',
    'toggle-follow': 'toggleFollow', 'dock': 'dock', 'toggle-hide': 'toggleHide'};

export default class BlueyExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._root = new Clutter.Actor({reactive: false});
        Main.layoutManager.uiGroup.add_child(this._root);

        this._cursor = new St.DrawingArea({width: 44, height: 44, reactive: false, opacity: 0});
        this._cursor.connect('repaint', area => this._paintCursor(area));
        this._bubble = new St.Label({style: 'background-color: rgba(255,255,255,0.97); color: #17151F; border-radius: 16px;' +
            'padding: 9px 14px; font-size: 15px; font-weight: 600; max-width: 380px;', reactive: false, opacity: 0});
        this._bubble.clutter_text.line_wrap = true;
        this._countdown = new St.Label({style: 'color: white; font-size: 64px; font-weight: 600;' +
            'text-shadow: 0 2px 8px rgba(0,0,0,0.6); font-feature-settings: "tnum";', reactive: false, visible: false});
        for (const a of [this._countdown, this._cursor, this._bubble]) this._root.add_child(a);
        this._cursorVisible = false;
        this._caption = '';
        this._raise = global.display.connect('restacked', () => this._toTop());
        this._layout();
        this._monitors = Main.layoutManager.connect('monitors-changed', () => this._layout());

        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/co/visionairy/Bluey/Overlay');
        this._name = Gio.bus_own_name_on_connection(Gio.DBus.session, 'co.visionairy.Bluey.Overlay',
            Gio.BusNameOwnerFlags.REPLACE, null, null);

        this._indicator = new PanelMenu.Button(0.5, 'Bluey');
        this._indicator.add_child(new St.Icon({icon_name: 'face-smile-symbolic', style_class: 'system-status-icon'}));
        this._buildMenu({});
        Main.panel.addToStatusArea(this.uuid, this._indicator);

        for (const [key, action] of Object.entries(KEYS)) {
            Main.wm.addKeybinding(key, this._settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.ALL,
                () => this._emit(action));
        }
    }

    disable() {
        for (const key of Object.keys(KEYS)) Main.wm.removeKeybinding(key);
        global.display.disconnect(this._raise);
        Main.layoutManager.disconnect(this._monitors);
        if (this._flashTimer) GLib.source_remove(this._flashTimer);
        this._dbus.unexport();
        Gio.bus_unown_name(this._name);
        this._indicator.destroy();
        this._root.destroy();
        this._dbus = this._indicator = this._root = this._settings = null;
    }

    _emit(action) { this._dbus?.emit_signal('Action', new GLib.Variant('(s)', [action])); }

    _toTop() { this._root?.get_parent()?.set_child_above_sibling(this._root, null); }

    _layout() {
        const m = Main.layoutManager.primaryMonitor;
        if (!m) return;
        this._countdown.set_position(m.x + m.width - 300, m.y + m.height - 110);
        this._home = [m.x + m.width / 2, m.y + m.height + 60];
        if (!this._cursorVisible) this._cursor.set_position(...this._home);
    }

    _paintCursor(area) {
        // An original arrow in the blueberry palette, white outline.
        const cr = area.get_context();
        const pts = [[4, 2], [4, 34], [13, 26], [20, 41], [27, 38], [20, 23], [32, 23]];
        cr.moveTo(...pts[0]);
        for (const p of pts.slice(1)) cr.lineTo(...p);
        cr.closePath();
        cr.setSourceRGBA(0.42, 0.53, 0.96, 1);
        cr.fillPreserve();
        cr.setSourceRGBA(1, 1, 1, 1);
        cr.setLineWidth(2.5);
        cr.stroke();
        cr.$dispose();
    }

    _placeBubble() {
        const visible = this._caption.length > 0;
        this._bubble.text = this._caption;
        if (!visible) { this._bubble.ease({opacity: 0, duration: 150}); return; }
        const m = Main.layoutManager.primaryMonitor;
        const [w, h] = this._bubble.get_preferred_size().slice(2);
        let x, y;
        if (this._cursorVisible) {
            [x, y] = [this._target[0] + 30, this._target[1] - h - 8];
        } else {
            [x, y] = [m.x + m.width / 2 - w / 2, m.y + m.height - h - 24];  // above the phone
        }
        x = Math.max(m.x + 8, Math.min(x, m.x + m.width - w - 8));
        y = Math.max(m.y + 8, Math.min(y, m.y + m.height - h - 8));
        this._bubble.set_position(Math.round(x), Math.round(y));
        this._bubble.ease({opacity: 255, duration: 150});
        this._toTop();
    }

    // D-Bus methods

    GetState() {
        const [x, y] = global.get_pointer();
        const w = global.display.focus_window;
        const app = w ? (Shell.WindowTracker.get_default().get_window_app(w)?.get_name() ?? w.get_wm_class() ?? '') : '';
        return [x, y, global.stage.width, global.stage.height, app];
    }

    Warp(x, y) {
        // Mutter 46+: the seat lives on the stage's Clutter context (get_default_backend() is gone).
        const backend = global.stage.context?.get_backend?.() ?? Clutter.get_default_backend?.();
        backend.get_default_seat().warp_pointer(Math.round(x), Math.round(y));
    }

    // Returns the flight time in seconds so the host can wait for the landing.
    SetCursor(visible, x, y) {
        const [fx, fy] = [this._cursor.x, this._cursor.y];
        const target = visible ? [x - 4, y - 2] : this._home;
        const distance = Math.hypot(target[0] - fx, target[1] - fy);
        const seconds = Math.min(1.1, 0.28 + distance / 2200);
        this._cursorVisible = visible;
        this._target = target;
        this._cursor.remove_all_transitions();
        this._cursor.ease({x: target[0], y: target[1], opacity: visible ? 255 : 0, duration: seconds * 1000,
            mode: Clutter.AnimationMode.EASE_IN_OUT_CUBIC, onComplete: () => this._placeBubble()});
        this._toTop();
        return seconds;
    }

    SetCaption(text) { this._caption = text; this._placeBubble(); }

    Flash(text) {
        this.SetCaption(text);
        if (this._flashTimer) GLib.source_remove(this._flashTimer);
        this._flashTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1600, () => {
            this._flashTimer = 0;
            if (this._caption === text) this.SetCaption('');
            return GLib.SOURCE_REMOVE;
        });
    }

    SetCountdown(text) {
        this._countdown.text = text;
        this._countdown.visible = text.length > 0;
        this._toTop();
    }

    SetHidden(hidden) { this._root.visible = !hidden; }

    SetMenu(json) {
        let state = {};
        try { state = JSON.parse(json); } catch { return; }
        this._buildMenu(state);
    }

    _buildMenu(s) {
        const menu = this._indicator.menu;
        menu.removeAll();
        const status = new PopupMenu.PopupMenuItem(s.status ?? 'Bluey host not running', {reactive: false});
        menu.addMenuItem(status);
        if (s.focus === 'running') menu.addAction('Pause focus', () => this._emit('focusPause'));
        if (s.focus === 'paused') menu.addAction('Resume focus', () => this._emit('focusResume'));
        if (s.focus === 'running' || s.focus === 'paused') menu.addAction('End focus', () => this._emit('focusEnd'));
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        for (const [label, key, action] of [['Developer Mode', 'developerMode', 'toggleDeveloperMode'],
            ['Computer control', 'computerControl', 'toggleComputerControl'], ['Follow mouse', 'followMouse', 'toggleFollow']]) {
            const item = new PopupMenu.PopupSwitchMenuItem(label, !!s[key]);
            item.connect('toggled', () => this._emit(action));
            menu.addMenuItem(item);
        }
        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        menu.addAction('Pair phone (QR)…', () => this._emit('pair'));
        menu.addAction('Gemini key…', () => this._emit('editKey'));
        menu.addAction('Personality…', () => this._emit('editPersonality'));
        menu.addAction('Stop actions (Ctrl+Alt+S)', () => this._emit('stop'));
        menu.addAction('Quit Bluey', () => this._emit('quit'));
    }
}
