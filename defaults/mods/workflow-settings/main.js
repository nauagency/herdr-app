import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, shared, setShared, exec, appHome, notify, run } from "herdr";

const CONFIG = "space-manager.config.v1";

function providerOf(profile) {
  return String(profile.provider || profile.agentFamily || profile.agent || "").toLowerCase();
}
function limitTone(t, value) {
  if (value == null) return t.dim;
  const n = Number(value);
  if (n <= 0) return t.blocked;
  if (n >= 80) return t.done;
  if (n >= 35) return t.working;
  return t.warning ?? t.working;
}

export default class WorkflowSettings extends View {
  init(_props, cx) {
    const p = props();
    const saved = (shared(CONFIG) ?? {})[p.spaceId] ?? {};
    this.leadProfileId = saved.leadProfileId ?? "";
    this.executorProfileIds = [...(saved.executorProfileIds ?? [])];
    this.profiles = [];
    this.loading = true;
    cx.spawn(async cx => {
      try {
        const helper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
        const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "list-all", ""]);
        const all = result.stdout.trim() ? JSON.parse(result.stdout) : [];
        this.profiles = all.filter(row => row.spaceId === p.spaceId && row.authenticated);
        // The host may choose the default workflow while this overlay is loading.
        // Read the shared config again so the selection shown here never goes stale.
        const latest = (shared(CONFIG) ?? {})[p.spaceId] ?? {};
        this.leadProfileId = latest.leadProfileId ?? this.leadProfileId;
        this.executorProfileIds = [...(latest.executorProfileIds ?? this.executorProfileIds)];
      } catch {}
      this.loading = false;
      cx.notify();
    });
  }

  row(id, title, subtitle, selected, action, usage = {}) {
    const t = theme();
    return h_flex().id(id).min_h(43).px(10).py(6).items_center().gap(8).rounded(8).cursor_pointer()
      .bg(selected ? t.selected : t.popover).hover(s => s.bg(t.hover)).on_click(action)
      .child(div().w(18).text_color(selected ? t.done : t.dim).child(selected ? "✓" : "○"))
      .child(v_flex().flex_1().min_w(0).gap(1)
        .child(div().truncate().text_size(12.3).text_color(t.foreground).child(title))
        .child(div().truncate().text_size(10.2).text_color(t.dim).child(subtitle)))
      .child(v_flex().w(58).items_end().text_size(9.5)
        .child(div().text_color(limitTone(t, usage.fiveHour)).child(`5H ${usage.fiveHour == null ? "—" : `${usage.fiveHour}%`}`))
        .child(div().text_color(limitTone(t, usage.week)).child(`W  ${usage.week == null ? "—" : `${usage.week}%`}`)));
  }

  toggleExecutor(id) {
    this.executorProfileIds = this.executorProfileIds.includes(id)
      ? this.executorProfileIds.filter(value => value !== id)
      : [...this.executorProfileIds, id];
  }

  async save() {
    const p = props();
    if (!this.leadProfileId || !this.executorProfileIds.length) {
      notify({ title: "Chưa đủ vai trò", body: "Chọn 1 Leader và ít nhất 1 worker thực thi.", level: "warning" });
      return;
    }
    const all = shared(CONFIG) ?? {};
    const current = all[p.spaceId] ?? {};
    const leader = this.profiles.find(profile => profile.id === this.leadProfileId);
    const leaderProvider = providerOf(leader);
    const patch = {
      workflowEnabled: true,
      workflowSetupConfirmed: true,
      leadProfileId: this.leadProfileId,
      profileId: this.leadProfileId,
      hostKey: leaderProvider.includes("claude") ? "claude" : leaderProvider.includes("codex") ? "codex" : leaderProvider.includes("antigravity") || leaderProvider.includes("gemini") ? "antigravity" : current.hostKey,
      model: "default",
      effort: leaderProvider.includes("gemini") ? "high" : "medium",
      orchestrationMode: "control-plane-v2",
      executorProfileIds: this.executorProfileIds.filter(id => id !== this.leadProfileId),
      maxReworkRounds: current.maxReworkRounds ?? 3,
      sameErrorLimit: current.sameErrorLimit ?? 2,
      maxExecutorBackups: current.maxExecutorBackups ?? 2,
      autoResumeLimit: current.autoResumeLimit ?? 1,
      minQuotaPercent: current.minQuotaPercent ?? 10,
      requireApprovalForMerge: true,
      forbidProviderSwitch: true,
    };
    setShared(CONFIG, { ...all, [p.spaceId]: { ...current, ...patch } });
    try {
      const helper = `${appHome()}/mods/space-manager-hostflow/workflow-policy.ps1`;
      await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "set", p.spaceId, this.leadProfileId, this.executorProfileIds.join(","), String(p.folder ?? "")]);
    } catch (error) {
      notify({ title: "Đã lưu giao diện", body: "Chưa đồng bộ được luật điều phối. Hãy mở lại thiết lập.", level: "warning" });
      return;
    }
    closeOverlay(p.overlay);
    run("space-manager-hostflow.apply-workflow");
    notify({ title: "Đã lưu workflow", body: "Leader sẽ trao đổi trực tiếp với bạn và điều phối worker; không còn Host AI trung gian.", level: "info" });
  }

  render() {
    const t = theme();
    const leadProfiles = this.profiles.filter(profile => profile.authenticated !== false);
    const executors = this.profiles.filter(profile => /antigravity|gemini/.test(providerOf(profile)));
    return v_flex().id("workflow-settings").w_full().h(620).min_h(0).p(11).gap(7).bg(t.popover)
      .child(div().px(4).pt(2).text_size(15).font_semibold().text_color(t.foreground).child("Workflow của Space"))
      .child(div().px(4).text_size(10.5).text_color(t.dim).child("Người dùng ↔ Leader → worker song song → mailbox → Leader tổng hợp → người dùng"))
      .child(div().px(4).pt(6).text_size(10.5).font_semibold().text_color(t.muted).child("LEADER · CODEX/CLAUDE MEDIUM · GEMINI HIGH"))
      .child(v_flex().h(125).min_h(60).overflow_y_scrollbar().gap(2)
        .children(leadProfiles.map(profile => this.row(`lead-${profile.id}`, `${providerOf(profile)} · ${profile.email || profile.id}`, "Trao đổi với bạn, giao việc và tổng hợp", profile.id === this.leadProfileId, (_e, cx) => { this.leadProfileId = profile.id; cx.notify(); }, profile.usage)))
        .when(!leadProfiles.length, el => el.child(div().px(10).py(10).text_size(11).text_color(t.blocked).child(this.loading ? "Đang kiểm tra…" : "Chưa có agent đã đăng nhập trong Space."))))
      .child(div().px(4).pt(5).text_size(10.5).font_semibold().text_color(t.muted).child("GEMINI THỰC THI · FLASH · HIGH"))
      .child(v_flex().h(180).min_h(80).overflow_y_scrollbar().gap(2)
        .children(executors.map(profile => this.row(`executor-${profile.id}`, `${providerOf(profile)} · ${profile.email || profile.id}`, "Có thể nhận việc hoặc làm backup", this.executorProfileIds.includes(profile.id), (_e, cx) => { this.toggleExecutor(profile.id); cx.notify(); }, profile.usage)))
        .when(!executors.length, el => el.child(div().px(10).py(10).text_size(11).text_color(t.blocked).child(this.loading ? "Đang kiểm tra…" : "Chưa có Gemini/Antigravity đã đăng nhập trong Space."))))
      .child(v_flex().px(4).py(5).gap(2).text_size(10.5).text_color(t.dim)
        .child("Backup: tối đa 2 Gemini khác trong Space; cùng jobId và worktree.")
        .child("Giới hạn: 3 vòng sửa, cùng lỗi tối đa 2 lần, tự khôi phục 1 lần, quota tối thiểu 10%.")
        .child("Không tự đổi nhà cung cấp/API. Merge, deploy, xoá dữ liệu và mở rộng phạm vi luôn hỏi bạn."))
      .child(h_flex().justify_end().pt(2)
        .child(h_flex().id("save-workflow").h(34).px(15).items_center().rounded(8).bg(t.solid).text_color(t.solid_foreground).cursor_pointer().hover(s => s.opacity(0.85)).on_click(() => this.save()).child("Lưu workflow")));
  }
}
