import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, spaces, panes, knownAgents, run, openOverlay, closeOverlay, props, window, keys, shared, setShared } from "herdr";

const KNOWN = "new-menu.agents";

function shortcut(name) {
  const k = keys().find(b => b.section === "global" && b.action === name);
  if (!k?.keys.trim()) return "";
  const mac = window()?.platform === "macos";
  const names = mac ? { ctrl: "⌃", alt: "⌥", shift: "⇧", cmd: "⌘", fn: "fn" } : { ctrl: "Ctrl", alt: "Alt", shift: "Shift", cmd: "Super", fn: "Fn" };
  const alias = { secondary: mac ? "cmd" : "ctrl", super: "cmd", win: "cmd" };
  return k.keys.trim().split(/\s+/).map(stroke => {
    const parts = stroke.split("-");
    let key = parts.pop();
    if (key === "") { key = "-"; parts.pop(); }
    const held = new Set(parts.map(m => alias[m.toLowerCase()] ?? m.toLowerCase()));
    if (/^[A-Z]$/.test(key)) held.add("shift");
    const label = key.length === 1 ? key.toUpperCase() : key[0].toUpperCase() + key.slice(1).toLowerCase();
    return [...Object.keys(names).filter(m => held.has(m)).map(m => names[m]), label].join(mac ? "" : "+");
  }).join(" ");
}

export default class NewMenu extends View {
  init(_props, cx) {
    const machine = spaces().find(s => s.active)?.machine;
    const where = machine ?? "";
    this.agents = shared(KNOWN)?.[where] ?? [];
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.spawn(async cx => {
      try {
        this.agents = await knownAgents({ on: machine });
        setShared(KNOWN, { ...shared(KNOWN), [where]: this.agents });
      }
      catch { this.failed = true; }
      cx.notify();
    });
  }
  row(id, icon, name, action, hint = "", enabled = true) {
    const t = theme();
    return h_flex().id(id).h(29).px(9).gap(9).rounded(7).items_center().flex_none()
      .text_color(enabled ? t.foreground : t.dim).when(enabled, el => el.hover(s => s.bg(t.selected)))
      .on_click(() => { if (enabled) { closeOverlay(props().overlay); action(); } })
      .child(icon).child(div().flex_1().child(name)).child(div().text_size(11).text_color(t.dim).child(hint));
  }
  render() {
    const t = theme();
    const space = spaces().find(s => s.active);
    const installed = this.agents.filter(a => a.installed);
    const choices = [...installed, ...this.agents.filter(a => !a.installed).slice(0, 4)];

    const multiAccounts = [1, 2, 3, 4, 5, 6].map(i => ({
      name: `Antigravity (Tài khoản ${i})`,
      key: `agy-${i}`,
      cmd: `agy-${i}`
    }));

    return v_flex().size_full().bg(t.popover).p(5).text_size(12.5)
      .id("new-menu").track_focus(this.handle)
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar()
        .child(this.row("terminal", svg("icons/shell.svg").size(14), "Terminal", () => run("tab.new", { space: space?.id }), shortcut("tab.new")))
        
        .child(div().px(9).pt(7).pb(2).text_size(11).font_semibold().text_color(t.accent).child("6 TÀI KHOẢN ANTIGRAVITY"))
        .children(multiAccounts.map((acc, idx) => 
          this.row(acc.key, image("icons/gemini.svg").size(14), acc.name, 
            () => run("tab.new", { name: acc.name, space: space?.id, argv: ["cmd.exe", "/c", acc.cmd] }), 
            String(idx + 1), true)
        ))

        .child(div().h(1).mx(4).my(5).bg(t.border))
        .child(div().px(9).pt(2).pb(2).text_size(11).text_color(t.dim).child("Start an agent (Gốc)"))
        .children(choices.map((a, i) => this.row(a.key, a.tint ? svg(a.icon).size(14).text_color(t.foreground) : image(a.icon).size(14), a.name,
          () => run("tab.new", { name: a.name, space: space?.id, argv: a.run }), a.installed ? (i < 9 ? String(i + 1) : "") : "not installed", a.installed)))

        .child(div().h(1).mx(4).my(5).bg(t.border))
        .child(this.row("space", div().w(14).child("+"), "New space", () => run("space.new"), shortcut("space.new")))
        .child(this.row("worktree", svg("mods/workspace-chrome/branch.svg").size(14), "New worktree…", () => openOverlay({ mod: "worktree", kind: "dialog", width: 460, height: 280, props: { space: space?.id, folder: panes().find(p => p.focused)?.cwd, action: "new" } }), "", Boolean(space)))
        .child(this.row("worktree-open", svg("mods/workspace-chrome/branch.svg").size(14), "Open worktree…", () => openOverlay({ mod: "worktree", kind: "dialog", width: 560, height: 480, props: { space: space?.id, folder: panes().find(p => p.focused)?.cwd, action: "open" } }), "", Boolean(space)))
      );
  }
}
