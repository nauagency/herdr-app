import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, exec, appHome, terminals, hc, notify } from "herdr";

const CONFIG = "space-manager.config.v1";
const FALLBACK = [
  { id: "gpt-6.1-sol", label: "GPT-6.1 Sol" },
  { id: "gpt-6.1-terra", label: "GPT-6.1 Terra" },
  { id: "gpt-6-astra", label: "GPT-6 Astra" },
  { id: "gpt-6-luna", label: "GPT-6 Luna" },
  { id: "gpt-5.6-sol", label: "GPT-5.6 Sol" },
];

export default class CodexModelPicker extends View {
  init(_props, cx) {
    this.model = props()?.model === "default" ? "" : props()?.model ?? "";
    this.effort = props()?.effort ?? "high";
    this.models = FALLBACK;
    this.loading = true;
    cx.spawn(async cx => {
      try {
        const script = `${appHome()}/mods/codex-model-picker/codex-models.mjs`;
        const result = await exec("node", [script, props()?.profileId ?? ""], { timeout: 15000 });
        const parsed = result.stdout.trim() ? JSON.parse(result.stdout) : [];
        if (Array.isArray(parsed) && parsed.length) this.models = parsed;
      } catch {}
      if (!this.model || !this.models.some(m => m.id === this.model)) this.model = this.models.find(m => m.isDefault)?.id ?? this.models[0]?.id ?? "";
      this.loading = false;
      cx.notify();
    });
  }

  option(id, label, selected, action) {
    const t = theme();
    return h_flex().id(id).min_h(34).px(10).items_center().rounded(8).cursor_pointer()
      .bg(selected ? t.selected : t.popover).text_color(t.foreground).hover(s => s.bg(t.hover))
      .on_click(action).child(div().flex_1().text_size(12.5).child(label)).when(selected, el => el.child(div().text_color(t.done).child("✓")));
  }

  async apply() {
    const p = props();
    const all = shared(CONFIG) ?? {};
    setShared(CONFIG, { ...all, [p.spaceId]: { ...(all[p.spaceId] ?? {}), model: this.model, effort: this.effort } });
    closeOverlay(p.overlay);
    const manager = terminals().find(t => t.labels?.["herdr.space"] === p.spaceId && t.labels?.["herdr.role"] === "manager");
    if (manager) {
      try { await hc(["send", manager.address, `/model ${this.model}`]); }
      catch { notify({ title: "Đã lưu model Codex", body: "Model mới sẽ áp dụng khi bật lại Manager.", level: "info" }); }
    }
  }

  render() {
    const t = theme();
    const efforts = ["low", "medium", "high", "xhigh", "max"];
    return v_flex().id("codex-model-picker").w_full().h(470).min_h(0).p(10).gap(7).bg(t.popover)
      .child(div().px(4).py(4).text_size(14).font_semibold().text_color(t.foreground).child("Model Codex của Manager"))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MODEL THEO TÀI KHOẢN"))
      .child(v_flex().h(275).min_h(120).overflow_y_scrollbar().gap(2)
        .children(this.models.map(m => this.option(`codex-${m.id}`, m.label, m.id === this.model, (_e, cx) => { this.model = m.id; cx.notify(); }))))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MỨC SUY LUẬN"))
      .child(h_flex().gap(5).flex_wrap().children(efforts.map(e => this.option(`effort-${e}`, e[0].toUpperCase() + e.slice(1), e === this.effort, (_e, cx) => { this.effort = e; cx.notify(); }))))
      .child(h_flex().pt(4).justify_end().child(h_flex().id("apply-codex-model").h(32).px(14).items_center().rounded(8).bg(t.solid).text_color(t.solid_foreground)
        .cursor_pointer().hover(s => s.opacity(0.85)).on_click(() => this.apply()).child("Áp dụng")));
  }
}
