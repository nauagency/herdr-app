import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, terminals, hc, notify } from "herdr";

const CONFIG = "space-manager.config.v1";
const MODELS = [
  { id: "sonnet", label: "Claude Sonnet (mới nhất)" },
  { id: "opus", label: "Claude Opus (mới nhất)" },
  { id: "haiku", label: "Claude Haiku (mới nhất)" },
  { id: "fable", label: "Claude Fable (mới nhất)" },
];

export default class ClaudeModelPicker extends View {
  init() {
    this.model = props()?.model === "default" ? "sonnet" : props()?.model ?? "sonnet";
    this.effort = props()?.effort ?? "high";
    if (!MODELS.some(m => m.id === this.model)) this.model = "sonnet";
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
      try {
        await hc(["send", manager.address, `/model ${this.model}`]);
        await hc(["send", manager.address, `/effort ${this.effort}`]);
      } catch { notify({ title: "Đã lưu model Claude", body: "Thiết lập mới sẽ áp dụng khi bật lại Manager.", level: "info" }); }
    }
  }

  render() {
    const t = theme();
    const efforts = ["low", "medium", "high", "xhigh", "max"];
    return v_flex().id("claude-model-picker").w_full().h(400).min_h(0).p(10).gap(7).bg(t.popover)
      .child(div().px(4).py(4).text_size(14).font_semibold().text_color(t.foreground).child("Model Claude của Manager"))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MODEL"))
      .child(v_flex().h(190).min_h(120).overflow_y_scrollbar().gap(2)
        .children(MODELS.map(m => this.option(`claude-${m.id}`, m.label, m.id === this.model, (_e, cx) => { this.model = m.id; cx.notify(); }))))
      .child(div().px(4).pt(3).text_size(10.5).font_semibold().text_color(t.muted).child("MỨC SUY LUẬN"))
      .child(h_flex().gap(5).flex_wrap().children(efforts.map(e => this.option(`effort-${e}`, e[0].toUpperCase() + e.slice(1), e === this.effort, (_e, cx) => { this.effort = e; cx.notify(); }))))
      .child(h_flex().pt(4).justify_end().child(h_flex().id("apply-claude-model").h(32).px(14).items_center().rounded(8).bg(t.solid).text_color(t.solid_foreground)
        .cursor_pointer().hover(s => s.opacity(0.85)).on_click(() => this.apply()).child("Áp dụng")));
  }
}
