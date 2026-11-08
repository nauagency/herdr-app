// New Space dialog: Name and Folder inputs with auto-increment naming.
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { run, props, closeOverlay, theme, pickFolder, spaces } from "herdr";

export default class NewSpaceDialog extends View {
  init(_props, cx) {
    const p = props() ?? {};
    const sp = spaces();
    const used = new Set();
    for (const s of sp) {
      const m = (s.name || "").match(/^Space\s+(\d+)$/i);
      if (m) used.add(parseInt(m[1], 10));
    }
    let n = 1;
    while (used.has(n)) n++;
    this.autoName = `Space ${n}`;
    this.nameText = this.autoName;
    this.folderText = p.folder ?? "";

    this.nameInput = InputState.new({ value: this.nameText });
    this.nameInput.set_selected_range({ start: 0, end: this.nameText.length });
    this.nameInput.on("change", (_e, cx) => {
      this.nameText = this.nameInput.value();
      cx.notify();
    });
    this.nameInput.on("submit", () => this.submit());
    this.nameFocused = true;
    this.nameInput.on("focus", (_e, cx) => { this.nameFocused = true; cx.notify(); });
    this.nameInput.on("blur", (_e, cx) => { this.nameFocused = false; cx.notify(); });

    this.folderInput = InputState.new({ value: this.folderText });
    this.folderInput.on("change", (_e, cx) => {
      this.folderText = this.folderInput.value();
      cx.notify();
    });
    this.folderInput.on("submit", () => this.submit());
    this.folderFocused = false;
    this.folderInput.on("focus", (_e, cx) => { this.folderFocused = true; cx.notify(); });
    this.folderInput.on("blur", (_e, cx) => { this.folderFocused = false; cx.notify(); });

    this.nameInput.focus();
    cx.timer.after(300, () => this.nameInput.focus());
    this.handle = cx.focus_handle();
  }

  chooseFolder(cx) {
    cx.spawn(async (cx) => {
      try {
        const picked = await pickFolder({ prompt: "Select" });
        if (picked) {
          this.folderText = picked;
          this.folderInput.set_value(picked);
          cx.notify();
        }
      } catch {}
    });
  }

  submit() {
    const p = props() ?? {};
    closeOverlay(p.overlay);
    const finalName = this.nameText.trim() || this.autoName;
    const args = { name: finalName };
    const folder = this.folderText.trim();
    if (folder) args.folder = folder;
    if (p.machine) args.machine = p.machine;
    run("space.new", args);
  }

  key(e, cx) {
    if (e.key === "escape") {
      closeOverlay(props()?.overlay);
      cx.stop_propagation();
    }
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    const label = (text) => div().pt(12).pb(5).text_size(11.5).font_medium().text_color(t.dim).child(text);
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover(s => s.opacity(0.88)).on_click(action).child(text);

    return v_flex().id("nau-new-space").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .child(
        h_flex().items_center().justify_between()
          .child(div().text_size(15).font_semibold().child("New Space" + (p.machine ? ` on ${p.machine}` : "")))
          .child(div().text_size(11).text_color(t.dim).child("Esc"))
      )
      .child(label("Name"))
      .child(
        Input.new(this.nameInput)
          .h(34).px(10).rounded(8)
          .border_1().border_color(this.nameFocused ? t.accent : t.input)
          .bg(t.background).text_size(12.8).text_color(t.foreground)
      )
      .child(label("Đường dẫn"))
      .child(
        h_flex().gap(8).items_center()
          .child(
            Input.new(this.folderInput)
              .flex_1().h(34).px(10).rounded(8)
              .border_1().border_color(this.folderFocused ? t.accent : t.input)
              .bg(t.background).text_size(12.8).text_color(t.foreground)
          )
          .child(
            h_flex().id("btn-browse").h(34).px(12).items_center().rounded(8)
              .border_1().border_color(t.input).bg(t.raised)
              .text_color(t.foreground).text_size(12).cursor_pointer()
              .hover(s => s.opacity(0.88))
              .on_click((_e, cx) => this.chooseFolder(cx))
              .child("Chọn thư mục…")
          )
      )
      .child(div().pt(4).text_size(11).text_color(t.dim).child("Để trống để dùng thư mục mặc định (~)"))
      .child(
        h_flex().pt(18).gap(8).justify_end()
          .child(button("sp-cancel", "Hủy", false, () => closeOverlay(p.overlay)))
          .child(button("sp-create", "Tạo", true, () => this.submit()))
      );
  }
}
