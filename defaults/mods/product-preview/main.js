import { View, div, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, theme, exec, appHome, notify, spaces } from "herdr";

function parseJsonOutput(stdout, fallback = []) {
  const clean = String(stdout ?? "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  return clean ? JSON.parse(clean) : fallback;
}

export default class ProductPreview extends View {
  init(_props, cx) {
    this.artifacts = props()?.artifacts ?? [];
    this.selected = Math.max(0, this.artifacts.length - 1);
    this.snapshot = "";
    this.loading = false;
    this.error = "";
    this.jobId = props()?.jobId ?? "";
    this.refresh(cx);
    cx.timer.every(props()?.auto ? 4000 : 8000, cx => this.refresh(cx));
  }

  artifact() { return this.artifacts[this.selected] ?? null; }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.spawn(async cx => {
      try {
        if (props()?.auto) {
          const spaceId = spaces().find(space => space.active)?.id ?? props()?.spaceId ?? "";
          if (spaceId) {
            const jobsHelper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
            const jobsResult = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "list", spaceId]);
            const jobs = parseJsonOutput(jobsResult.stdout);
            const latest = [...jobs].reverse().find(job => (job.artifacts ?? []).length > 0);
            if (latest) {
              const next = latest.artifacts ?? [];
              const changed = this.jobId !== latest.id || this.artifacts.length !== next.length;
              this.jobId = latest.id;
              this.artifacts = next;
              this.selected = Math.max(0, next.length - 1);
              if (changed) this.snapshot = "";
            }
          }
        }
        const artifact = this.artifact();
        if (!artifact || artifact.type !== "preview") {
          this.error = "";
          this.loading = false;
          cx.notify();
          return;
        }
        const helper = `${appHome()}/mods/product-preview/preview-helper.ps1`;
        const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "capture", artifact.value, this.jobId || "preview"], { timeout: 30000 });
        this.snapshot = result.stdout.trim();
        this.error = "";
      } catch (error) { this.error = String(error.message ?? error); }
      this.loading = false;
      cx.notify();
    });
  }

  select(index, cx) {
    this.selected = index;
    this.snapshot = "";
    this.error = "";
    this.refresh(cx);
    cx.notify();
  }

  openArtifact() {
    const artifact = this.artifact();
    if (!artifact) return;
    const helper = `${appHome()}/mods/product-preview/preview-helper.ps1`;
    exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "open", artifact.value, this.jobId || "preview"])
      .catch(error => notify({ title: "Không mở được sản phẩm", body: String(error.message ?? error), level: "warning" }));
  }

  button(id, label, action, primary = false) {
    const t = theme();
    return h_flex().id(id).h(28).px(10).items_center().rounded(7).border_1().border_color(primary ? t.solid : t.input)
      .bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground).text_size(10.5)
      .cursor_pointer().hover(s => s.opacity(0.85)).on_click(action).child(label);
  }

  render() {
    const t = theme();
    const artifact = this.artifact();
    const previewPath = artifact?.type === "image" ? artifact.value : this.snapshot;
    return v_flex().id("product-preview").size_full().min_h(0).p(10).gap(8).bg(t.canvas).text_color(t.foreground)
      .child(h_flex().items_center().justify_between()
        .child(v_flex().min_w(0).gap(1)
          .child(div().truncate().text_size(13).font_semibold().child(artifact?.label ?? "Preview sản phẩm"))
          .child(div().truncate().text_size(9.5).text_color(t.dim).child(`${this.jobId || "Tự động theo dõi Space"}${artifact?.from ? ` · phản hồi từ ${artifact.from}` : ""}`)))
        .child(h_flex().gap(5)
          .when(artifact?.type === "preview", row => row.child(this.button("refresh-preview", this.loading ? "Đang tải…" : "Làm mới", (_e, cx) => this.refresh(cx))))
          .when(Boolean(artifact), row => row.child(this.button("open-product", "Mở sản phẩm", () => this.openArtifact(), true)))))
      .child(h_flex().flex_1().min_h(0).gap(8)
        .child(v_flex().w(170).min_w(140).overflow_y_scrollbar().gap(3)
          .children(this.artifacts.map((item, index) => v_flex().id(`artifact-${item.id ?? index}`).px(8).py(7).gap(2).rounded(7)
            .bg(index === this.selected ? t.selected : t.surface).cursor_pointer().hover(s => s.bg(t.hover)).on_click((_e, cx) => this.select(index, cx))
            .child(div().truncate().text_size(10.5).child(item.label || item.type))
            .child(div().truncate().text_size(9).text_color(t.dim).child(`${item.type}${item.from ? ` · ${item.from}` : ""}`)))))
        .child(v_flex().flex_1().min_w(0).min_h(0).rounded(9).border_1().border_color(t.border).bg(t.background).items_center().justify_center()
          .when(Boolean(previewPath), el => el.child(image(previewPath).size_full().rounded(8)))
          .when(!previewPath && Boolean(this.error), el => el.child(div().p(20).text_size(11).text_color(t.blocked).child(this.error)))
          .when(!previewPath && !this.error, el => el.child(div().p(20).text_size(11).text_color(t.dim).child(artifact ? "Định dạng này mở bằng ứng dụng phù hợp." : "Agent chưa gửi sản phẩm xem trước.")))));
  }
}
