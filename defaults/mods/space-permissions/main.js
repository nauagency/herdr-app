import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, notify } from "herdr";

const CONFIG = "space-manager.config.v1";

export default class SpacePermissions extends View {
  init() {
    const p = props();
    const saved = (shared(CONFIG) ?? {})[p.spaceId] ?? {};
    this.mode = saved.approvalMode ?? "auto";
  }

  option(id, label, detail, warning = false) {
    const t = theme();
    const selected = this.mode === id;
    return h_flex().id(`space-permission-${id}`).min_h(58).px(11).py(8).items_center().gap(9).rounded(9).border_1()
      .border_color(selected ? t.accent : t.border).bg(selected ? t.selected : t.surface).cursor_pointer()
      .hover(s => s.bg(t.hover)).on_click((_e, cx) => { this.mode = id; cx.notify(); })
      .child(div().w(20).text_size(15).text_color(selected ? t.done : t.dim).child(selected ? "✓" : "○"))
      .child(v_flex().flex_1().min_w(0).gap(2)
        .child(div().text_size(12.2).font_semibold().text_color(warning ? t.blocked : t.foreground).child(label))
        .child(div().text_size(10.2).text_color(t.dim).child(detail)));
  }

  save() {
    const p = props();
    const all = shared(CONFIG) ?? {};
    const current = all[p.spaceId] ?? {};
    setShared(CONFIG, { ...all, [p.spaceId]: { ...current, approvalMode: this.mode } });
    closeOverlay(p.overlay);
    const label = { ask: "Cần duyệt", auto: "Tự duyệt", full: "Toàn quyền" }[this.mode];
    notify({ title: `Quyền Space: ${label}`, body: "Áp dụng cho Host, Lead và mọi agent trong Space khi được mở lại.", level: this.mode === "full" ? "warning" : "info" });
  }

  render() {
    const t = theme();
    return v_flex().id("space-permissions").size_full().p(12).gap(8).bg(t.popover)
      .child(div().text_size(15).font_semibold().text_color(t.foreground).child("Quyền của toàn Space"))
      .child(div().pb(3).text_size(10.5).text_color(t.dim).child("Chọn một lần cho Host, Lead và tất cả agent hiện tại hoặc thêm sau này trong Space này."))
      .child(this.option("ask", "Cần duyệt", "Hỏi bạn trước những thao tác cần thêm quyền."))
      .child(this.option("auto", "Tự duyệt", "Tự xử lý thao tác an toàn trong thư mục dự án."))
      .child(this.option("full", "Toàn quyền", "Không giới hạn tệp và Internet. Chỉ dùng cho Space tin cậy.", true))
      .child(h_flex().flex_1().items_end().justify_end()
        .child(h_flex().id("save-space-permissions").h(34).px(15).items_center().rounded(8).bg(t.solid).text_color(t.solid_foreground)
          .cursor_pointer().hover(s => s.opacity(0.85)).on_click(() => this.save()).child("Áp dụng cho Space")));
  }
}
