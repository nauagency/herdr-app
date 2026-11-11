import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, exec, terminals, hc, notify, appHome } from "herdr";

const CONFIG = "space-manager.config.v1";
const FALLBACK = [
  ["gemini-4-argon-low", "Gemini 4 Argon"],
  ["gemini-4-argon-medium", "Gemini 4 Argon"],
  ["gemini-4-argon-high", "Gemini 4 Argon"],
  ["gemini-3.8-flash-low", "Gemini 3.8 Flash"],
  ["gemini-3.8-flash-medium", "Gemini 3.8 Flash"],
  ["gemini-3.8-flash-high", "Gemini 3.8 Flash"],
  ["claude-opus-5-5-low", "Claude Opus 5.5"],
  ["claude-opus-5-5-medium", "Claude Opus 5.5"],
  ["claude-opus-5-5-high", "Claude Opus 5.5"],
  ["claude-sonnet-5-5-low", "Claude Sonnet 5.5"],
  ["claude-sonnet-5-5-medium", "Claude Sonnet 5.5"],
  ["claude-sonnet-5-5-high", "Claude Sonnet 5.5"],
  ["gpt-oss-120b-medium", "GPT-OSS 120B"],
];

function splitModel(id) {
  const match = String(id ?? "").match(/^(.*)-(low|medium|high|xhigh|max)$/i);
  return match ? { base: match[1], effort: match[2].toLowerCase() } : { base: id || "gemini-3.8-flash", effort: "high" };
}

export default class ManagerModelPicker extends View {
  init(_props, cx) {
    const current = splitModel(props()?.model);
    this.base = current.base;
    this.effort = current.effort;
    this.instanceId = props()?.profileId ?? "";
    this.models = this.instanceId ? [] : FALLBACK.map(([id, label]) => ({ id, label }));
    this.loadFailed = false;
    this.loading = true;
    cx.spawn(async cx => {
      try {
        if (this.instanceId) {
          const helper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
          const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "get-models", this.instanceId], { timeout: 30000 });
          const catalog = result.stdout.trim() ? JSON.parse(result.stdout) : null;
          this.models = catalog?.source === "instance" && Array.isArray(catalog.models) ? catalog.models : [];
          this.loadFailed = !this.models.length;
        }
      } catch { this.loadFailed = true; }
      this.loading = false;
      this.ensureChoice();
      cx.notify();
    });
  }

  groups() {
    const seen = new Set();
    return this.models.filter(model => {
      const base = splitModel(model.id).base;
      if (seen.has(base)) return false;
      seen.add(base);
      return true;
    }).map(model => ({ base: splitModel(model.id).base, label: model.label }));
  }

  efforts() {
    const order = ["low", "medium", "high", "xhigh", "max"];
    const available = new Set(this.models.filter(m => splitModel(m.id).base === this.base).map(m => splitModel(m.id).effort));
    return order.filter(e => available.has(e));
  }

  ensureChoice() {
    const groups = this.groups();
    if (!groups.some(g => g.base === this.base)) this.base = groups[0]?.base ?? this.base;
    const efforts = this.efforts();
    if (!efforts.includes(this.effort)) this.effort = efforts.includes("high") ? "high" : efforts[0] ?? this.effort;
  }

  async apply() {
    const p = props();
    const all = shared(CONFIG) ?? {};
    const model = `${this.base}-${this.effort}`;
    setShared(CONFIG, { ...all, [p.spaceId]: { ...(all[p.spaceId] ?? {}), model } });
    closeOverlay(p.overlay);
    const manager = terminals().find(t => t.labels?.["herdr.space"] === p.spaceId && t.labels?.["herdr.role"] === "manager");
    if (manager) {
      try { await hc(["send", manager.address, `/model ${model}`]); }
      catch (e) { notify({ title: "Đã lưu model cho lần bật sau", body: "Phiên Manager hiện tại chưa đổi được model.", level: "warning" }); }
    }
  }

  option(id, label, selected, action) {
    const t = theme();
    return h_flex().id(id).min_h(34).px(10).items_center().rounded(8).cursor_pointer()
      .bg(selected ? t.selected : t.popover).text_color(t.foreground).hover(s => s.bg(t.hover))
      .on_click(action).child(div().flex_1().text_size(12.5).child(label)).when(selected, el => el.child(div().text_color(t.done).child("✓")));
  }

  render() {
    const t = theme();
    const groups = this.groups();
    const efforts = this.efforts();
    return v_flex().id("manager-model-picker").w_full().h(470).min_h(0).p(10).gap(7).bg(t.popover)
      .child(div().px(4).py(4).text_size(14).font_semibold().text_color(t.foreground).child("Model của Manager"))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MODEL"))
      .child(v_flex().h(275).min_h(120).overflow_y_scrollbar().gap(2)
        .children(groups.map(g => this.option(`model-${g.base}`, g.label, g.base === this.base, (_e, cx) => { this.base = g.base; this.ensureChoice(); cx.notify(); })))
        .when(this.loadFailed, el => el.child(div().px(10).py(12).text_size(11).text_color(t.blocked).child("Không đọc được danh sách model của tài khoản này."))))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MỨC SUY LUẬN"))
      .child(h_flex().gap(5).flex_wrap().children(efforts.map(e => this.option(`effort-${e}`, e[0].toUpperCase() + e.slice(1), e === this.effort, (_e, cx) => { this.effort = e; cx.notify(); }))))
      .when(groups.length > 0, root => root.child(h_flex().pt(4).justify_end().child(h_flex().id("apply-model").h(32).px(14).items_center().rounded(8).bg(t.solid).text_color(t.solid_foreground)
        .cursor_pointer().hover(s => s.opacity(0.85)).on_click(() => this.apply()).child("Áp dụng"))));
  }
}
