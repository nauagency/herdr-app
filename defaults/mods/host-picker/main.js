import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, knownAgents, exec, appHome, run } from "herdr";

const CONFIG = "space-manager.config.v1";

export default class HostPicker extends View {
  init(_props, cx) {
    this.profiles = [];
    this.agents = [];
    this.loading = true;
    this.mode = props()?.mode === "login" ? "login" : "accounts";
    cx.spawn(async cx => {
      try {
        try { this.agents = await knownAgents({ on: props()?.machine ?? null }); }
        catch { this.agents = await knownAgents(); }
        if (!props()?.machine) {
          const helper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
          const r = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "list-all", ""]);
          this.profiles = r.stdout.trim() ? JSON.parse(r.stdout) : [];
        }
      } catch {}
      this.loading = false;
      cx.notify();
    });
  }

  choose(patch, start = true) {
    const p = props();
    const all = shared(CONFIG) ?? {};
    setShared(CONFIG, { ...all, [p.spaceId]: { ...(all[p.spaceId] ?? {}), ...patch } });
    closeOverlay(p.overlay);
    if (start) run("space-manager-hostflow.start");
  }

  row(id, title, subtitle, action) {
    const t = theme();
    return v_flex().id(id).min_h(46).px(10).py(7).gap(2).rounded(8).cursor_pointer().hover(s => s.bg(t.hover)).on_click(action)
      .child(div().truncate().text_size(12.5).text_color(t.foreground).child(title))
      .child(div().truncate().text_size(10.5).text_color(t.dim).child(subtitle));
  }

  render() {
    const t = theme();
    const logged = [...this.profiles].filter(p => p.authenticated && p.email)
      .sort((a, b) => (a.createdAt ?? "").localeCompare(b.createdAt ?? "") || String(a.id).localeCompare(String(b.id)));
    const installed = this.agents.filter(a => a.installed);
    return v_flex().id("host-picker").w_full().h(500).min_h(0).p(10).gap(6).bg(t.popover)
      .child(h_flex().px(4).py(5).items_center().gap(8)
        .when(this.mode === "login", el => el.child(div().id("back-accounts").w(25).h(25).rounded(6).items_center().justify_center().cursor_pointer().hover(s => s.bg(t.raised)).on_click((_e, cx) => { this.mode = "accounts"; cx.notify(); }).child("‹")))
        .child(div().text_size(14).font_semibold().text_color(t.foreground).child(this.mode === "login" ? "Chọn loại agent" : "Chọn Leader cho Space")))
      .when(this.mode === "accounts", root => root
        .child(h_flex().id("login-another").h(38).px(10).items_center().gap(8).rounded(8).border_1().border_color(t.input).bg(t.raised).text_color(t.foreground).cursor_pointer().hover(s => s.bg(t.hover))
          .on_click((_e, cx) => { this.mode = "login"; cx.notify(); }).child(div().text_size(17).child("＋")).child(div().text_size(12.5).font_medium().child("Đăng nhập tài khoản khác")))
        .child(div().px(4).pt(6).text_size(10.5).font_semibold().text_color(t.muted).child("TÀI KHOẢN ĐÃ ĐĂNG NHẬP"))
        .child(v_flex().h(365).min_h(120).overflow_y_scrollbar().gap(2)
          .children(logged.map(p => { const key = p.provider || p.agentFamily || p.agent; const id = p.instanceId || p.id; return this.row(`instance-${id}`, `${key} · ${p.email}`, `Leader · ${p.loginState === "authenticated" ? "Đã đăng nhập" : p.loginState}`, () => this.choose({ hostKey: key, profileId: id, leadProfileId: id, orchestrationMode: "leader-direct-v1", model: key === "antigravity" ? "gemini-3.8-flash-high" : "default", effort: key === "antigravity" ? "high" : "medium" })); }))
          .when(!logged.length, el => el.child(div().px(10).py(10).text_size(11).text_color(t.dim).child(this.loading ? "Đang kiểm tra…" : "Chưa có tài khoản đã lưu")))))
      .when(this.mode === "login", root => root
        .child(div().px(4).text_size(10.5).text_color(t.dim).child("Agent sẽ mở hồ sơ mới để bạn đăng nhập."))
        .child(v_flex().h(410).min_h(160).overflow_y_scrollbar().gap(2)
          .children(installed.map(a => this.row(`login-${a.key}`, a.name, "Tạo hồ sơ mới và mở đăng nhập ngay", () => this.choose({ hostKey: a.key, profileId: "", model: a.key === "antigravity" ? "gemini-3.8-flash-high" : "default" }))))
          .when(!installed.length, el => el.child(div().px(10).py(10).text_size(11).text_color(t.dim).child(this.loading ? "Đang tải danh sách agent…" : "Không tìm thấy agent đã cài")))));
  }
}
