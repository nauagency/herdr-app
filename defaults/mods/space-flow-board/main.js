import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, theme, exec, appHome, shared, setShared, spaces, agents, terminals, openOverlay, nextCommand, hc, notify, run } from "herdr";

// Dashboard hierarchy and fleet/handoff interaction model adapted from Knowns UI
// (MIT License, knowns-dev/knowns-ui). Reimplemented in native Herdr GPUI.

const CONFIG = "space-manager.config.v1";
const FLOW_PROFILES = "space-flow.profiles.v1";
const DISMISSED_JOBS = "space-flow-dismissed-jobs.v1";
const GRAPH_ROW = 58; // height of a call-graph row; every node tile is centered on it so lines align
const graphNodeSize = id => id === "leader" ? 58 : String(id).startsWith("worker-") ? 54 : 46; // tile px: lead > worker > others
// 0..1..0 smooth pulse (ease-in-out cosine) with the given period in ms, like the Knowns "kn-breathe" keyframe.
const breathe = (period = 2400, phase = 0) => (1 - Math.cos(2 * Math.PI * (((Date.now() + phase) % period) / period))) / 2;
const STEPS = ["Leader", "Worker", "Check", "Duyệt", "Bạn"];

function stageIndex(job) {
  if (job.status === "completed" || job.stage === "done") return 6;
  return { planning: 1, execution: 2, "automatic-gate": 3, review: 4, approval: 5 }[job.stage] ?? 2;
}
function asArray(value) { return value == null ? [] : Array.isArray(value) ? value : [value]; }
function parseJsonOutput(stdout, fallback = []) {
  const clean = String(stdout ?? "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  return clean ? JSON.parse(clean) : fallback;
}
function routeLabel(mode) {
  return { "fast-path": "Luồng nhanh", "lead-first": "Qua Lead", "ask-user": "Hỏi bạn" }[mode] ?? "Chưa phân luồng";
}
function limitTone(t, value) {
  if (value == null) return t.dim;
  const number = Number(value);
  if (number <= 0) return t.blocked;
  if (number >= 80) return t.done;
  if (number >= 35) return t.working;
  return t.warning ?? t.working;
}

export default class SpaceFlowBoard extends View {
  init(_props, cx) {
    this.jobs = [];
    this.mailbox = [];
    this.profiles = props()?.profiles ?? [];
    this.loading = false;
    this.pendingDecision = null;
    this.selectedJobId = null;
    this.selectedGraphNode = null;
    this.graphZoom = 1;
    this.graphZoomTarget = 1;
    this.graphAnimating = false;
    this.graphZooming = false;
    this.graphPopping = false;
    this.graphSelectedAt = 0;
    this.taskMode = "status";
    this.showMailbox = false;
    this.graphPan = { x: 0, y: 0 };
    this.graphDrag = null;
    this.graphDragExpiresAt = 0;
    this.refresh(cx);
    cx.timer.every(4000, cx => this.refresh(cx));
    cx.timer.every(1000, cx => cx.notify());
    // Zoom/popover transitions repaint at ~30fps; ambient pulses at ~15fps to keep the whole view light.
    let tick = 0;
    cx.timer.every(33, cx => { tick++; if (this.graphZooming || this.graphPopping || (this.graphAnimating && tick % 2 === 0)) cx.notify(); });
    cx.timer.every(60, cx => {
      if (this.graphDrag && Date.now() > this.graphDragExpiresAt) this.endGraphDrag(cx);
    });
    cx.spawn(async cx => {
      for (;;) {
        const command = await nextCommand();
        if (command === "decide-job" && this.pendingDecision) await this.decideJob(cx);
        cx.notify();
      }
    });
  }

  spaceId() { return props()?.spaceId ?? spaces().find(space => space.active)?.id ?? ""; }
  config() { return (shared(CONFIG) ?? {})[this.spaceId()] ?? {}; }

  refresh(cx) {
    if (this.loading) return;
    const cached = (shared(FLOW_PROFILES) ?? {})[this.spaceId()] ?? [];
    if (cached.length) this.profiles = cached;
    this.loading = true;
    cx.spawn(async cx => {
      try {
        const jobsHelper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
        const profilesHelper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
        const [jobs, mailbox, profiles] = await Promise.all([
          exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "list", this.spaceId()]),
          exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "mailbox", this.spaceId()]),
          exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", profilesHelper, "list", this.spaceId()]),
        ]);
        this.jobs = parseJsonOutput(jobs.stdout);
        this.mailbox = parseJsonOutput(mailbox.stdout);
        const loadedProfiles = parseJsonOutput(profiles.stdout);
        if (loadedProfiles.length) this.profiles = loadedProfiles;
      } catch (error) {
        this.error = String(error.message ?? error);
      }
      this.loading = false;
      cx.notify();
    });
  }

  profileName(id, fallback = "") {
    const profile = this.profiles.find(row => row.id === id);
    return profile?.email || profile?.displayName || profile?.agentFamily || id || fallback || "Chưa phân công";
  }

  modelLabel(profile, role = "Agent") {
    if (!profile) return role === "Leader" ? "Codex · medium" : "Chưa chọn model";
    const provider = String(profile.provider ?? profile.agentFamily ?? profile.agent ?? "").toLowerCase();
    const cfg = this.config();
    let raw = profile.runtimeModel || profile.requestedModel || profile.usage?.model || "";
    if (!raw || raw === "default" || raw === "codex") {
      if (provider.includes("antigravity")) raw = role === "Leader" ? (cfg.model || "gemini-3.8-flash") : "gemini-3.8-flash";
      else if (provider.includes("codex")) raw = "codex";
      else if (provider.includes("claude")) raw = "claude";
      else raw = provider || "model mặc định";
    }
    const pretty = String(raw)
      .replace(/^gemini[- ]?3\.8[- ]?flash(?:[- ]?high)?$/i, "Gemini 3.8 Flash")
      .replace(/^gemini[- ]?4[- ]?argon$/i, "Gemini 4 Argon")
      .replace(/^codex$/i, "Codex")
      .replace(/^claude$/i, "Claude")
      .replace(/[-_]+/g, " ")
      .replace(/\b\w/g, char => char.toUpperCase());
    const effort = String(profile.runtimeEffort || profile.requestedEffort || (provider.includes("antigravity") ? "high" : provider.includes("codex") || provider.includes("claude") ? "medium" : "")).toLowerCase();
    return effort ? `${pretty} · ${effort}` : pretty;
  }

  role(profile) {
    const cfg = this.config();
    if (profile.id === cfg.leadProfileId || profile.id === cfg.profileId) return "Leader";
    if ((cfg.executorProfileIds ?? []).includes(profile.id)) return "Executor";
    return "Agent";
  }

  live(profile) {
    const terminal = (this.frame?.terminals ?? terminals()).find(row => row.labels?.["herdr.profile"] === profile.id);
    const agent = terminal ? (this.frame?.agents ?? agents()).find(row => row.address === terminal.address) : null;
    const status = agent?.status ?? (terminal ? "idle" : profile.running ? "idle" : "offline");
    return { terminal, agent, status };
  }

  statusLabel(status) {
    return { working: "Đang làm", blocked: "Cần bạn", done: "Vừa hoàn thành", idle: "Sẵn sàng", offline: "Chưa chạy" }[status] ?? "Sẵn sàng";
  }

  jobStatusLabel(status) {
    return { queued: "Đang chờ", working: "Đang làm", checking: "Đang kiểm tra", "needs-review": "Chờ Leader", "needs-input": "Chờ Leader", "awaiting-approval": "Chờ bạn", completed: "Hoàn thành", failed: "Thất bại" }[status] ?? status;
  }

  chip(text, tone = "muted") {
    const t = theme();
    return div().px(6).py(2).rounded(5).bg(t.raised).text_size(9).text_color(t[tone] ?? t.muted).child(text);
  }

  action(id, label, handler, primary = false) {
    const t = theme();
    return h_flex().id(id).h(27).px(9).items_center().rounded(7).border_1().border_color(primary ? t.solid : t.input)
      .bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground).text_size(10)
      .cursor_pointer().hover(style => style.opacity(0.85)).on_click(handler).child(label);
  }

  askDecision(job, approved) {
    this.pendingDecision = { job, approved };
    openOverlay({ mod: "confirm", kind: "dialog", width: 450, height: 220, props: {
      title: approved ? `Xác nhận cho ${job.id}?` : `Từ chối ${job.id}?`,
      detail: approved
        ? "Leader được tiếp tục đúng hành động đang chờ; merge, deploy hoặc xoá dữ liệu ngoài phạm vi vẫn phải hỏi lại."
        : "Leader không được thực hiện hành động đang chờ và phải điều chỉnh kế hoạch hoặc báo lại.",
      command: { name: "space-flow-board.decide-job" },
    }});
  }

  async decideJob(cx) {
    const pending = this.pendingDecision;
    this.pendingDecision = null;
    const manager = terminals().find(row => row.labels?.["herdr.space"] === this.spaceId() && row.labels?.["herdr.role"] === "manager");
    if (!pending?.job || !manager) return;
    try {
      const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
      const detail = pending.approved ? "User approved the pending action." : "User denied the pending action.";
      await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "update", this.spaceId(), pending.job.id, "working", detail]);
      await hc(["send", manager.address, pending.approved
        ? `Người dùng đã xác nhận hành động đang chờ của jobId=${pending.job.id}. Tiếp tục đúng phạm vi đã duyệt và báo lại kết quả.`
        : `Người dùng từ chối hành động đang chờ của jobId=${pending.job.id}. Không thực hiện; điều chỉnh kế hoạch hoặc báo lại.`]);
      this.refresh(cx);
    } catch (error) {
      notify({ title: "Chưa gửi được quyết định", body: String(error.message ?? error), level: "warning" });
    }
  }

  progress(job) {
    const t = theme();
    const index = stageIndex(job);
    return h_flex().gap(3).children(STEPS.map((label, i) => v_flex().flex_1().min_w(0).gap(3)
      .child(div().h(3).rounded(2).bg(i < index ? t.done : i === index ? t.working : t.border))
      .child(div().truncate().text_size(8.5).text_color(i <= index ? t.foreground : t.dim).child(label))));
  }

  dismissJob(job, cx) {
    const all = shared(DISMISSED_JOBS) ?? {};
    const ids = new Set(all[this.spaceId()] ?? []);
    ids.add(job.id);
    setShared(DISMISSED_JOBS, { ...all, [this.spaceId()]: [...ids] });
    if (this.selectedJobId === job.id) this.selectedJobId = null;
    cx.notify();
  }

  jobCard(job) {
    const t = theme();
    const feedback = job.result || job.recoveryNote || "Chưa có phản hồi";
    const selected = this.selectedJobId === job.id;
    return v_flex().id(`flow-job-${job.id}`).p(10).gap(6).rounded(9).border_1().border_color(job.status === "awaiting-approval" ? t.blocked : selected ? t.accent : t.border).bg(selected ? t.selected : t.surface)
      .cursor_pointer().hover(style => style.bg(t.hover)).on_click((_e, cx) => { cx.stop_propagation(); this.selectedJobId = job.id; cx.notify(); })
      .child(h_flex().items_center().justify_between().gap(8)
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().truncate().text_size(11.5).font_semibold().child(job.task))
          .child(div().truncate().text_size(9.5).text_color(t.dim).child(`${job.id} · ${this.profileName(job.assigneeProfile, job.assignee)}`)))
        .child(h_flex().items_center().gap(5)
          .child(this.chip(routeLabel(job.routeMode), job.routeMode === "fast-path" ? "done" : job.routeMode === "ask-user" ? "blocked" : "accent"))
          .child(this.chip(this.jobStatusLabel(job.status), job.status === "awaiting-approval" ? "blocked" : job.status === "needs-review" ? "accent" : "working"))
          .when(job.status === "needs-review" || job.status === "completed", el => el.child(div().id(`dismiss-job-${job.id}`).size(20).rounded(6).items_center().justify_center().text_size(13).text_color(t.muted)
            .cursor_pointer().hover(style => style.bg(t.hover).text_color(t.foreground)).on_click((event, cx) => { cx.stop_propagation(); this.dismissJob(job, cx); }).child("×")))))
      .when(Boolean(job.routeReason), el => el.child(div().truncate().text_size(9).text_color(t.muted).child(`Phân luồng: ${job.routeReason}`)))
      .child(this.progress(job))
      .child(div().truncate().text_size(9).text_color(t.dim)
        .child(`${job.contextProfile === "lean" ? "Lean" : "Full"} · ${asArray(job.checkpoints).length} checkpoint · ${asArray(job.evidence).length} bằng chứng · ${asArray(job.artifacts).length} sản phẩm · ${asArray(job.reviewFindings).filter(f => f.status === "open").length} review mở`))
      .child(h_flex().items_center().justify_between().gap(8)
        .child(div().flex_1().truncate().text_size(9.5).text_color(t.muted).child(`Phản hồi: ${feedback}`)))
      .when(job.status === "awaiting-approval", el => el.child(h_flex().justify_end().gap(6)
        .child(this.action(`flow-deny-${job.id}`, "Từ chối", () => this.askDecision(job, false)))
        .child(this.action(`flow-approve-${job.id}`, "Xác nhận", () => this.askDecision(job, true), true))))
      .when((job.previousAssignees ?? []).length > 0 || Number(job.backupCount ?? 0) > 0, el => el.child(div().truncate().text_size(9).text_color(t.dim)
        .child(`Handoff: ${(job.previousAssignees ?? []).join(" → ")}${job.assignee ? ` → ${job.assignee}` : ""} · ${job.backupCount ?? 0} backup`)));
  }

  stat(label, value, tone = "foreground", filter = "") {
    const t = theme();
    const selected = Boolean(filter) && this.config().agentStatusFilter === filter;
    const select = (_event, cx) => {
        const spaceId = this.spaceId();
        const all = shared(CONFIG) ?? {};
        setShared(CONFIG, { ...all, [spaceId]: { ...(all[spaceId] ?? {}), agentStatusFilter: selected ? "" : filter } });
        cx.notify();
    };
    return h_flex().id(`status-filter-${filter || label}`).flex_1().min_w(0).px(11).py(9)
      .bg(selected ? t.selected : t.canvas).border_1().border_color(selected ? t.accent : t.border)
      .when(Boolean(filter), el => el.cursor_pointer().hover(style => style.bg(t.hover)).on_click(select))
      .child(v_flex().gap(2)
        .child(div().truncate().text_size(9.5).text_color(t.dim).child(label))
        .child(div().text_size(18).font_semibold().text_color(t[tone] ?? t.foreground).child(String(value))));
  }

  handoffRow(job) {
    const t = theme();
    const last = asArray(job.checkpoints).slice(-1)[0];
    const from = (job.previousAssignees ?? []).slice(-1)[0] || "Leader";
    const to = this.profileName(job.assigneeProfile, job.assignee);
    const text = last?.summary || job.result || job.recoveryNote || job.task;
    return v_flex().px(2).py(7).gap(2).border_b(1).border_color(t.border)
      .child(h_flex().items_center().gap(5)
        .child(div().size(6).rounded(4).bg(job.status === "awaiting-approval" ? t.blocked : job.status === "needs-review" ? t.accent : t.working))
        .child(div().flex_1().truncate().text_size(9.8).font_medium().child(`${from} → ${to}`))
        .child(div().text_size(8.8).text_color(t.dim).child(this.jobStatusLabel(job.status))))
      .child(div().pl(11).truncate().text_size(9).text_color(t.muted).child(text));
  }

  mailboxRow(message) {
    const t = theme();
    const linkedJob = this.jobs.find(job => job.id === message.jobId);
    const finalCheckpoint = asArray(linkedJob?.checkpoints).slice(-1)[0];
    const from = linkedJob && message.from === linkedJob.assignee ? this.profileName(linkedJob.assigneeProfile, message.from) : (message.from || "Agent");
    const summary = message.type === "history.imported" ? (finalCheckpoint?.summary || message.summary) : message.summary;
    const labels = { "task.assigned": "Giao việc", "result.submitted": "Đã trả kết quả", "worker.blocked": "Cần hỗ trợ", "result.accepted": "Đã tổng hợp", "history.imported": "Lịch sử" };
    const tone = message.type === "worker.blocked" ? t.blocked : message.type === "result.submitted" || message.type === "result.accepted" ? t.done : t.accent;
    const time = message.createdAt ? new Date(message.createdAt).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }) : "";
    return v_flex().id(`mailbox-${message.id}`).px(2).py(7).gap(3).border_b(1).border_color(t.border)
      .child(h_flex().items_center().gap(5)
        .child(div().size(6).rounded(4).bg(tone))
        .child(div().flex_1().truncate().text_size(9.8).font_medium().child(`${from} → ${message.to || "Leader"}`))
        .child(this.chip(labels[message.type] || message.type || "Thông báo", message.type === "worker.blocked" ? "blocked" : "muted"))
        .when(Boolean(time), el => el.child(div().text_size(8.5).text_color(t.dim).child(time))))
      .child(div().pl(11).text_size(9).text_color(t.muted).max_h(44).overflow_hidden().child(summary || "Không có nội dung"));
  }

  // Graph coordinates are node centers; every node tile is centered on its row (GRAPH_ROW tall), so lines
  // run center-to-center and are inset by half the tile size in pixels (tiles don't scale with zoom).
  graphLine(x, y, width, vertical = false, active = false, insetStart = 0, insetEnd = 0, dashed = false) {
    const t = theme();
    const z = this.graphZoom;
    const th = active ? 2 : 1.25;
    const len = Math.max(1, width * z - insetStart - insetEnd);
    const line = div().absolute().bg(active ? t.accent : t.border)
      .when(active, el => el.opacity(0.55 + 0.45 * breathe(2400, x * 3 + y * 5)));
    const placed = vertical
      ? line.left(x * z + this.graphPan.x - th / 2).top(y * z + this.graphPan.y + insetStart).w(th).h(len)
      : line.left(x * z + this.graphPan.x + insetStart).top(y * z + this.graphPan.y - th / 2).h(th).w(len);
    if (!active) return placed;
    // A bright dot travels along active edges so direction and liveliness are visible at a glance.
    const raw = ((Date.now() + x * 7 + y * 3) % 1600) / 1600;
    const f = raw < 0.5 ? 2 * raw * raw : 1 - Math.pow(-2 * raw + 2, 2) / 2;
    const dot = div().absolute().size(6).rounded(3).bg(t.accent)
      .opacity(Math.sin(Math.PI * raw));
    return placed.child(vertical ? dot.top(f * len - 3).left(th / 2 - 3) : dot.left(f * len - 3).top(th / 2 - 3));
  }

  endGraphDrag(cx) {
    if (!this.graphDrag) return;
    this.graphDrag = null;
    this.graphDragExpiresAt = 0;
    cx.notify();
  }

  graphNode(id, title, subtitle, x, y, tone = "muted", active = false, onClick = null, program = null) {
    const t = theme();
    const z = this.graphZoom;
    const color = t[tone] ?? t.muted;
    const fallbackIcon = id === "user" ? "user"
      : id === "host" ? "orchestrator"
      : id === "lead" ? "lead"
      : id === "gate" ? "gate"
      : id === "pool" ? "pool"
      : "worker";
    const selected = this.selectedGraphNode?.id === id;
    const size = graphNodeSize(id);
    const iconPx = Math.round(size * 0.5);
    // (x, y) is the top-left of a 112px-wide, GRAPH_ROW-tall slot in graph units. Center the tile on the
    // zoomed slot center so lines always meet it, whatever the tile size or zoom.
    const centerX = (x + 56) * z + this.graphPan.x;
    const centerY = (y + GRAPH_ROW / 2) * z + this.graphPan.y;
    const k = active ? breathe(2400, x * 2 + y) : 0;
    const grow = 6 * k;
    const tile = h_flex().id(`graph-tile-${id}`).size(size).flex_none().rounded(14).border_1()
      .border_color(selected ? t.solid : active ? color : t.border).bg(selected ? t.selected : t.surface)
      .items_center().justify_center().text_color(color)
      .cursor_pointer().hover(el => el.bg(t.hover).border_color(t.solid))
      .when(active, el => el.shadow_md())
      .child(program?.icon
        ? (program.tint
          ? svg(program.icon).size(iconPx).flex_none().text_color(color)
          : image(program.icon).size(iconPx).flex_none())
        : svg(`mods/space-flow-board/icons/${fallbackIcon}.svg`).size(iconPx).flex_none().text_color(color));
    // Breathing ring: expands and fades once per cycle around nodes that are working.
    const ring = div().absolute().left(-grow - 1).top(-grow - 1).size(size + 2 * grow + 2).rounded(14 + grow).border_1()
      .border_color(color).opacity(0.1 + 0.7 * (1 - k));
    return v_flex().id(`graph-${id}`).absolute().left(centerX - 56).top(centerY - size / 2).w(112).items_center().gap(8)
      .cursor_pointer().on_click((_e, cx) => { cx.stop_propagation(); this.endGraphDrag(cx); this.selectedGraphNode = this.selectedGraphNode?.id === id ? null : { id, title, subtitle }; this.graphSelectedAt = Date.now(); if (onClick) onClick(_e, cx); cx.notify(); })
      .child(div().relative().size(size).flex_none().when(active, el => el.child(ring)).child(tile))
      .child(v_flex().w_full().items_center().gap(1)
        .child(div().w_full().truncate().text_center().text_size(11).font_semibold().child(title))
        .child(div().w_full().truncate().text_center().text_size(9).text_color(t.dim).child(subtitle)));
  }

  graphPopover(sel, slot, d, graphW) {
    const t = theme();
    const z = this.graphZoom;
    const size = graphNodeSize(sel.id);
    const W = 264;
    const cx0 = (slot.x + 56) * z + this.graphPan.x;
    const cy0 = (slot.y + GRAPH_ROW / 2) * z + this.graphPan.y;
    const right = cx0 + size / 2 + 16;
    const left = right + W > graphW * z - 4 ? cx0 - size / 2 - 16 - W : right;
    // Entrance like Knowns "kn-rise": fade in while sliding up 6px over 200ms.
    const p = Math.min(1, (Date.now() - (this.graphSelectedAt || 0)) / 200);
    const eased = 1 - Math.pow(1 - p, 3);
    this.graphPopping = p < 1;
    const color = t[d.tone] ?? t.muted;
    return v_flex().id("graph-popover").absolute().left(Math.max(4, left)).top(Math.max(4, cy0 - 36) + 6 * (1 - eased)).w(W).p(12).gap(9)
      .rounded(14).border_1().border_color(t.border).bg(t.surface).shadow_xl().opacity(eased)
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .child(h_flex().items_start().gap(8)
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().truncate().text_size(12.5).font_semibold().child(sel.title))
          .child(div().truncate().text_size(9.5).text_color(t.dim).child(sel.subtitle)))
        .child(h_flex().id("graph-popover-close").size(22).flex_none().items_center().justify_center().rounded(6).text_size(14).text_color(t.muted)
          .cursor_pointer().hover(el => el.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { cx.stop_propagation(); this.selectedGraphNode = null; cx.notify(); }).child("×")))
      .child(h_flex().items_center().gap(6).px(8).py(5).rounded(8).bg(t.raised)
        .child(div().size(6).flex_none().rounded(3).bg(color))
        .child(div().flex_1().truncate().text_size(10).text_color(color).font_medium().child(d.status)))
      .children((d.rows ?? []).map(([k, v]) => h_flex().items_center().justify_between().gap(8)
        .child(div().text_size(9.5).text_color(t.dim).child(k))
        .child(div().max_w(160).truncate().text_size(9.5).child(v))))
      .when((d.calls ?? []).length > 0, el => el.child(v_flex().gap(5).pt(8).border_t(1).border_color(t.border)
        .child(div().text_size(9).text_color(t.dim).font_semibold().child("CUỘC GỌI"))
        .children(d.calls.map(c => h_flex().items_center().gap(6)
          .child(div().text_size(10).text_color(t.accent).child("→"))
          .child(div().flex_none().max_w(84).truncate().text_size(10).font_semibold().child(c.to))
          .child(div().flex_1().min_w(0).truncate().text_size(9.5).text_color(t.muted).child(c.text))
          .child(div().flex_none().text_size(9).text_color(t.dim).child(c.meta))))))
      .when(Boolean(d.terminal), el => el.child(this.action("graph-popover-terminal", "Mở terminal", (_e, cx) => { cx.stop_propagation(); run("pane.focus", { terminal: d.terminal.address }); })));
  }

  jobTone(job) {
    return job.status === "awaiting-approval" || job.status === "failed" ? "blocked"
      : job.status === "needs-review" || job.status === "needs-input" ? "accent"
      : job.status === "completed" ? "done"
      : job.status === "queued" ? "muted"
      : "working";
  }

  jobElapsed(job) {
    const start = Date.parse(job.createdAt ?? job.startedAt ?? "");
    if (!Number.isFinite(start)) return "";
    const finished = job.status === "completed" || job.status === "failed";
    const stop = finished ? Date.parse(job.updatedAt ?? job.completedAt ?? "") : Date.now();
    const s = Math.max(0, Math.round(((Number.isFinite(stop) ? stop : Date.now()) - start) / 1000));
    return s >= 3600 ? `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m` : `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  taskAvatar(profile, size = 28) {
    const t = theme();
    const program = profile ? this.live(profile).terminal?.program : null;
    const px = Math.round(size * 0.58);
    return h_flex().size(size).flex_none().rounded(8).border_1().border_color(t.border).bg(t.raised).items_center().justify_center()
      .child(program?.icon
        ? (program.tint ? svg(program.icon).size(px).flex_none().text_color(t.foreground) : image(program.icon).size(px).flex_none())
        : svg("mods/space-flow-board/icons/worker.svg").size(px).flex_none().text_color(t.muted));
  }

  taskCard(job) {
    const t = theme();
    const profile = this.profiles.find(row => row.id === job.assigneeProfile);
    const tone = this.jobTone(job);
    const color = t[tone] ?? t.muted;
    const selected = this.selectedJobId === job.id;
    const needs = job.status === "awaiting-approval";
    const feedback = job.result || job.recoveryNote || "";
    const elapsed = this.jobElapsed(job);
    const checkpoints = asArray(job.checkpoints).length;
    return v_flex().id(`task-${job.id}`).p(9).gap(7).rounded(10).border_1()
      .border_color(needs ? t.blocked : selected ? t.accent : t.border).bg(selected ? t.selected : t.surface)
      .cursor_pointer().hover(el => el.bg(t.hover).border_color(needs ? t.blocked : t.dim))
      .on_click((_e, cx) => { cx.stop_propagation(); this.selectedJobId = job.id; cx.notify(); })
      .child(h_flex().items_center().gap(7)
        .child(this.taskAvatar(profile))
        .child(v_flex().flex_1().min_w(0)
          .child(div().truncate().text_size(10.5).font_semibold().child(this.profileName(job.assigneeProfile, job.assignee)))
          .child(div().truncate().text_size(9).text_color(t.dim).child(profile ? this.modelLabel(profile, this.role(profile)) : "Chưa chọn model")))
        .child(h_flex().flex_none().items_center().gap(4).px(6).py(2).rounded(6).bg(t.raised)
          .child(div().size(5).rounded(3).bg(color))
          .child(div().text_size(9).text_color(color).child(this.jobStatusLabel(job.status)))))
      .child(div().text_size(11).font_semibold().max_h(30).overflow_hidden().child(job.task))
      .when(Boolean(feedback), el => el.child(h_flex().gap(6)
        .child(div().w(2).flex_none().rounded(1).bg(needs ? t.blocked : t.border))
        .child(div().flex_1().min_w(0).max_h(28).overflow_hidden().text_size(9.5).text_color(t.muted).child(feedback))))
      .when(job.status === "working" || job.status === "checking", el => el.child(this.progress(job)))
      .when(needs, el => el.child(h_flex().justify_end().gap(6)
        .child(this.action(`task-deny-${job.id}`, "Từ chối", (_e, cx) => { cx.stop_propagation(); this.askDecision(job, false); }))
        .child(this.action(`task-approve-${job.id}`, "Xác nhận", (_e, cx) => { cx.stop_propagation(); this.askDecision(job, true); }, true))))
      .child(h_flex().items_center().gap(6).text_size(9).text_color(t.dim)
        .when(Boolean(elapsed), el => el.child(div().child(elapsed)))
        .child(div().flex_1().truncate().child(`${elapsed ? "· " : ""}${job.id}${checkpoints ? ` · ${checkpoints} bước` : ""}`))
        .when(job.status === "needs-review" || job.status === "completed", el => el.child(div().id(`task-dismiss-${job.id}`).size(18).rounded(5).items_center().justify_center().text_size(12).text_color(t.muted)
          .cursor_pointer().hover(s => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { cx.stop_propagation(); this.dismissJob(job, cx); }).child("×"))));
  }

  // Task columns drive the agent filter in the left sidebar (shared config key read by space-manager-hostflow).
  toggleStatusFilter(key, cx) {
    const spaceId = this.spaceId();
    const all = shared(CONFIG) ?? {};
    const current = (all[spaceId] ?? {}).agentStatusFilter ?? "";
    setShared(CONFIG, { ...all, [spaceId]: { ...(all[spaceId] ?? {}), agentStatusFilter: current === key ? "" : key } });
    cx.notify();
  }

  taskColumn(key, label, color, cards, count) {
    const t = theme();
    const active = (this.config().agentStatusFilter ?? "") === key;
    // Header sits above its own bordered cell (like Knowns); both are clickable and filter agents on the left.
    return v_flex().id(`task-col-${key}`).flex_1().min_w(0).h_full().min_h(0).gap(8)
      .child(h_flex().id(`task-col-head-${key}`).items_center().gap(6).px(4).h(22).rounded(6).cursor_pointer()
        .when(active, el => el.bg(t.selected)).hover(el => el.bg(t.hover))
        .on_click((_e, cx) => this.toggleStatusFilter(key, cx))
        .child(div().size(7).flex_none().rounded(4).bg(color))
        .child(div().flex_1().min_w(0).truncate().text_size(10.5).font_semibold().text_color(active ? t.accent : t.foreground).child(label))
        .child(div().text_size(10).text_color(t.dim).child(String(count))))
      .child(v_flex().id(`task-cell-${key}`).flex_1().min_h(0).rounded(12).border_1().border_color(active ? t.accent : t.border).bg(t.raised).p(6)
        .cursor_pointer().on_click((_e, cx) => this.toggleStatusFilter(key, cx))
        .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().gap(6).children(cards)
          .when(!count, el => el.child(div().py(14).text_size(9.5).text_color(t.dim).text_center().child("Trống")))));
  }

  taskBoard(jobs, orderedProfiles, untrackedWorking, waitingUser, mailboxCount) {
    const t = theme();
    const mode = this.taskMode;
    const filter = this.config().agentStatusFilter ?? "";
    const newest = [...jobs].reverse();
    const defs = [
      { key: "queued", label: "Queued", color: t.dim, match: job => job.status === "queued" },
      { key: "running", label: "Running", color: t.working, match: job => job.status === "working" || job.status === "checking" },
      { key: "review", label: "Needs review", color: t.blocked, match: job => ["needs-review", "needs-input", "awaiting-approval"].includes(job.status) },
      { key: "done", label: "Done", color: t.done, match: job => job.status === "completed" || job.status === "failed", limit: 10 },
    ];
    let body;
    if (mode === "assignee") {
      // Matrix like Knowns: status headers on top, one row per assignee, one cell per status.
      const known = new Set(orderedProfiles.map(profile => profile.id));
      const groups = orderedProfiles.map(profile => ({ key: profile.id, profile, label: this.profileName(profile.id), jobs: newest.filter(job => job.assigneeProfile === profile.id) }));
      const orphan = newest.filter(job => !known.has(job.assigneeProfile));
      if (orphan.length) groups.push({ key: "none", profile: null, label: "Chưa phân công", jobs: orphan });
      const header = h_flex().flex_none().gap(8).children(defs.map(def => h_flex().id(`task-matrix-head-${def.key}`).flex_1().min_w(0).items_center().gap(6).px(4).h(22).rounded(6).cursor_pointer()
        .when(filter === def.key, el => el.bg(t.selected)).hover(el => el.bg(t.hover)).on_click((_e, cx) => this.toggleStatusFilter(def.key, cx))
        .child(div().size(7).flex_none().rounded(4).bg(def.color))
        .child(div().flex_1().min_w(0).truncate().text_size(10.5).font_semibold().child(def.label))
        .child(div().text_size(10).text_color(t.dim).child(String(newest.filter(def.match).length)))));
      const rows = groups.map(group => v_flex().id(`task-row-${group.key}`).flex_none().gap(6)
        .child(h_flex().items_center().gap(7).h(26).px(2)
          .child(this.taskAvatar(group.profile, 22))
          .child(div().flex_1().min_w(0).truncate().text_size(10.5).font_semibold().child(group.label))
          .child(div().text_size(10).text_color(t.dim).child(String(group.jobs.length))))
        .child(h_flex().gap(8).children(defs.map(def => v_flex().id(`task-cell-${group.key}-${def.key}`).flex_1().min_w(0).min_h(88).rounded(12).border_1().border_color(filter === def.key ? t.accent : t.border).bg(t.raised).p(6).gap(6)
          .cursor_pointer().on_click((_e, cx) => this.toggleStatusFilter(def.key, cx))
          .children(group.jobs.filter(def.match).slice(0, def.limit ?? 50).map(job => this.taskCard(job)))))));
      body = v_flex().w_full().h(360).flex_none().gap(8).child(header)
        .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().gap(12).children(rows)
          .when(!groups.length, el => el.child(div().p(12).text_size(10).text_color(t.dim).child("Chưa có agent nào."))));
    } else {
      const columns = defs.map(def => {
        const rows = newest.filter(def.match).slice(0, def.limit ?? 50);
        const cards = rows.map(job => this.taskCard(job));
        if (def.key === "running") untrackedWorking.forEach(profile => cards.push(this.liveActivityCard(profile)));
        return this.taskColumn(def.key, def.label, def.color, cards, rows.length + (def.key === "running" ? untrackedWorking.length : 0));
      });
      body = h_flex().w_full().h(360).flex_none().gap(8).children(columns);
    }
    const seg = (id, label, value) => h_flex().id(id).h(24).px(11).items_center().rounded(7).text_size(10).cursor_pointer()
      .bg(mode === value ? t.surface : t.raised).text_color(mode === value ? t.foreground : t.muted)
      .when(mode === value, el => el.border_1().border_color(t.border).shadow_sm())
      .hover(el => el.text_color(t.foreground))
      .on_click((_e, cx) => { this.taskMode = value; cx.notify(); }).child(label);
    const open = this.showMailbox;
    return v_flex().flex_1().h_full().min_w(0).min_h(0).gap(8)
      .child(h_flex().items_center().justify_between().gap(8)
        .child(h_flex().items_center().gap(8)
          .child(div().text_size(12).font_semibold().child("Tasks"))
          .child(div().text_size(9.5).text_color(waitingUser ? t.blocked : t.dim).child(`${waitingUser ? `${waitingUser} chờ bạn · ` : ""}${jobs.length} việc`)))
        .child(h_flex().items_center().gap(8)
          .child(h_flex().p(2).gap(2).rounded(9).bg(t.raised).child(seg("tasks-mode-status", "Status", "status")).child(seg("tasks-mode-assignee", "Assignee", "assignee")))
          .child(h_flex().id("tasks-mailbox").h(28).px(10).gap(6).items_center().rounded(8).border_1().text_size(10).cursor_pointer()
            .border_color(open ? t.accent : t.input).bg(open ? t.selected : t.raised).text_color(t.foreground)
            .hover(el => el.bg(t.hover))
            .on_click((_e, cx) => { this.showMailbox = !this.showMailbox; cx.notify(); })
            .child("Mailbox").child(this.chip(String(mailboxCount), mailboxCount ? "accent" : "muted")))))
      .child(body);
  }

  callGraph(activeJobs, orderedProfiles, workingProfiles) {
    const t = theme();
    // Ease the displayed zoom toward its target for smooth zooming (the 50ms timer keeps repainting meanwhile).
    const dz = this.graphZoomTarget - this.graphZoom;
    if (Math.abs(dz) > 0.002) { this.graphZoom += dz * 0.28; this.graphZooming = true; } else { this.graphZoom = this.graphZoomTarget; this.graphZooming = false; }
    const cfg = this.config();
    const leader = orderedProfiles.find(profile => profile.id === cfg.leadProfileId) ?? orderedProfiles.find(profile => profile.id === cfg.profileId);
    const workerJobs = activeJobs.filter(job => job.assigneeProfile && ["queued", "working", "checking"].includes(job.status)).slice(0, 8);
    const waitingLeader = activeJobs.filter(job => job.status === "needs-review" || job.status === "needs-input").length;
    const rowGap = 88;
    const workerYs = workerJobs.map((_job, index) => 72 + index * rowGap);
    const graphW = 720;
    const graphH = Math.max(350, 144 + Math.max(1, workerJobs.length) * rowGap);
    const centerY = workerJobs.length ? (workerYs[0] + workerYs[workerYs.length - 1]) / 2 : 148;
    const leaderActive = leader ? this.live(leader).status === "working" : false;
    const anyGate = workerJobs.some(job => job.status === "checking");
    const grid = [];
    for (let x = 0; x < graphW; x += 45) grid.push(div().absolute().left(x).top(0).w(1).h(graphH).bg(t.border).opacity(x % 90 === 0 ? 0.2 : 0.09));
    for (let y = 0; y < graphH; y += 45) grid.push(div().absolute().left(0).top(y).h(1).w(graphW).bg(t.border).opacity(y % 90 === 0 ? 0.2 : 0.09));

    const workActive = workerJobs.some(job => ["queued", "working", "checking"].includes(job.status));
    this.graphAnimating = workActive || leaderActive || anyGate;
    // Node centers (graph units): slot x + 56, row y + GRAPH_ROW / 2. Lines run center-to-center, inset by
    // half of each end node's tile so they touch the tile edges at any zoom.
    const rowY = y => y + GRAPH_ROW / 2;
    const userX = 68, leaderX = 264, workerX = 456, gateX = 620;
    const trunkIn = (leaderX + workerX) / 2, trunkOut = (workerX + gateX) / 2;
    const hUser = graphNodeSize("user") / 2, hLead = graphNodeSize("leader") / 2, hWork = graphNodeSize("worker-") / 2, hGate = graphNodeSize("gate") / 2;
    const midY = rowY(centerY);
    const firstWorkerCenter = workerJobs.length ? rowY(workerYs[0]) : midY;
    const lastWorkerCenter = workerJobs.length ? rowY(workerYs[workerYs.length - 1]) : midY;
    const links = [this.graphLine(userX, midY, leaderX - userX, false, leaderActive, hUser, hLead)];
    if (workerJobs.length) {
      links.push(this.graphLine(leaderX, midY, trunkIn - leaderX, false, workActive, hLead, 0));
      links.push(this.graphLine(trunkIn, firstWorkerCenter, Math.max(1, lastWorkerCenter - firstWorkerCenter), true, workActive));
      workerYs.forEach(y => {
        links.push(this.graphLine(trunkIn, rowY(y), workerX - trunkIn, false, workActive, 0, hWork));
        links.push(this.graphLine(workerX, rowY(y), trunkOut - workerX, false, anyGate, hWork, 0));
      });
      links.push(this.graphLine(trunkOut, firstWorkerCenter, Math.max(1, lastWorkerCenter - firstWorkerCenter), true, anyGate));
      links.push(this.graphLine(trunkOut, midY, gateX - trunkOut, false, anyGate, 0, hGate));
    } else {
      links.push(this.graphLine(leaderX, midY, gateX - leaderX, false, false, hLead, hGate));
    }

    const nodes = [
      this.graphNode("user", "Bạn", "Giao yêu cầu", 12, centerY, "foreground", false),
      this.graphNode("leader", "Leader", waitingLeader ? `${waitingLeader} kết quả chờ xử lý` : this.modelLabel(leader, "Leader"), 208, centerY, waitingLeader ? "working" : "accent", leaderActive, null, leader ? this.live(leader).terminal?.program : null),
      this.graphNode("gate", "Local Gate", anyGate ? "Kiểm tra & evidence" : "Chờ kết quả", 564, centerY, anyGate ? "done" : "muted", anyGate),
      this.graphNode("pool", "Agent rảnh", `${Math.max(0, orderedProfiles.length - workingProfiles.length)} sẵn sàng`, 208, centerY + 108, "muted", false),
    ];
    workerJobs.forEach((job, index) => {
      const profile = this.profiles.find(row => row.id === job.assigneeProfile);
      const isWorking = ["queued", "working", "checking"].includes(job.status);
      nodes.push(this.graphNode(`worker-${job.id}`, `Worker ${index + 1}`, this.modelLabel(profile, "Worker"), 400, workerYs[index], isWorking ? "working" : "done", isWorking, (_e, cx) => { this.selectedJobId = job.id; cx.notify(); }, profile ? this.live(profile).terminal?.program : null));
    });

    const waitingUser = activeJobs.filter(job => job.status === "awaiting-approval").length;
    const slots = { user: { x: 12, y: centerY }, leader: { x: 208, y: centerY }, gate: { x: 564, y: centerY }, pool: { x: 208, y: centerY + 108 } };
    workerJobs.forEach((job, index) => { slots[`worker-${job.id}`] = { x: 400, y: workerYs[index] }; });
    const idleProfiles = orderedProfiles.filter(profile => this.live(profile).status !== "working");
    const details = {
      user: { tone: waitingUser ? "blocked" : "muted", status: waitingUser ? `${waitingUser} việc chờ bạn xác nhận` : "Sẵn sàng giao việc", rows: [["Vai trò", "Người giao yêu cầu"]], calls: [] },
      leader: {
        tone: leaderActive ? "working" : "accent", status: leaderActive ? "Đang làm" : "Sẵn sàng",
        rows: [["Model", this.modelLabel(leader, "Leader")], ["Chờ xử lý", String(waitingLeader)], ["Đang giao", String(workerJobs.length)]],
        calls: workerJobs.map((job, index) => ({ to: `Worker ${index + 1}`, text: job.task, meta: this.jobStatusLabel(job.status) })),
        terminal: leader ? this.live(leader).terminal : null,
      },
      gate: { tone: anyGate ? "done" : "muted", status: anyGate ? "Đang kiểm tra" : "Chờ kết quả", rows: [["Đang kiểm tra", String(workerJobs.filter(job => job.status === "checking").length)]], calls: [] },
      pool: { tone: "muted", status: `${idleProfiles.length} sẵn sàng`, rows: [], calls: idleProfiles.slice(0, 6).map(profile => ({ to: this.profileName(profile.id), text: this.modelLabel(profile), meta: this.statusLabel(this.live(profile).status) })) },
    };
    workerJobs.forEach((job, index) => {
      const profile = this.profiles.find(row => row.id === job.assigneeProfile);
      details[`worker-${job.id}`] = {
        tone: this.jobTone(job), status: this.jobStatusLabel(job.status),
        rows: [["Model", this.modelLabel(profile, "Worker")], ["Agent", this.profileName(job.assigneeProfile, job.assignee)], ["Giai đoạn", String(job.stage ?? "execution")], ["Job", job.id]],
        calls: [{ to: "Leader", text: job.result || job.task, meta: this.jobElapsed(job) }],
        terminal: profile ? this.live(profile).terminal : null,
      };
    });
    const picked = this.selectedGraphNode;
    const popover = picked && slots[picked.id] && details[picked.id] ? this.graphPopover(picked, slots[picked.id], details[picked.id], graphW) : null;
    if (!popover) this.graphPopping = false;

    const selected = this.selectedGraphNode;
    return v_flex().flex_none().rounded(12).border_1().border_color(t.border).bg(t.surface).overflow_hidden()
      .child(h_flex().h(40).px(12).items_center().justify_between().border_b(1).border_color(t.border)
        .child(h_flex().items_center().gap(7)
          .child(div().size(7).rounded(4).bg(t.done).opacity(this.graphAnimating ? 0.45 + 0.55 * breathe() : 1))
          .child(div().text_size(11.5).font_semibold().child("Call graph"))
          .child(this.chip(`${workerJobs.length} đang chạy`)))
        .child(h_flex().items_center().gap(4)
          .when(Boolean(selected), el => el.child(div().mr(6).max_w(180).truncate().text_size(9).text_color(t.muted).child(`${selected?.title} · ${selected?.subtitle}`)))
          .child(this.action("graph-zoom-out", "−", (_e, cx) => { this.graphZoomTarget = Math.max(0.7, this.graphZoomTarget - 0.15); cx.notify(); }))
          .child(this.action("graph-zoom-in", "+", (_e, cx) => { this.graphZoomTarget = Math.min(1.45, this.graphZoomTarget + 0.15); cx.notify(); }))
          .child(this.action("graph-fit", "Fit", (_e, cx) => { this.graphZoomTarget = Math.max(0.7, Math.min(1, 350 / graphH)); this.graphPan = { x: 0, y: 0 }; cx.notify(); }))))
      .child(h_flex().w_full().h(Math.min(430, graphH * this.graphZoom)).justify_center().overflow_x_scrollbar().overflow_y_scrollbar()
        .child(div().id("call-graph-canvas").relative().w(graphW * this.graphZoom).h(graphH * this.graphZoom).flex_none().cursor_grab()
          .on_mouse_down("left", (event, cx) => { this.graphDrag = { x: event.position.x, y: event.position.y, pan: { ...this.graphPan } }; this.graphDragExpiresAt = Date.now() + 140; cx.stop_propagation(); })
          .on_mouse_move((event, cx) => { if (!this.graphDrag) return; const now = Date.now(); if (now > this.graphDragExpiresAt) { this.endGraphDrag(cx); return; } this.graphDragExpiresAt = now + 140; this.graphPan = { x: this.graphDrag.pan.x + event.position.x - this.graphDrag.x, y: this.graphDrag.pan.y + event.position.y - this.graphDrag.y }; if (!this.lastGraphPaint || now - this.lastGraphPaint >= 16) { this.lastGraphPaint = now; cx.notify(); } })
          .on_mouse_up("left", (_event, cx) => { this.endGraphDrag(cx); cx.stop_propagation(); })
          .on_hover((hovered, cx) => { if (!hovered) this.endGraphDrag(cx); })
          .on_mouse_down_out((_event, cx) => this.endGraphDrag(cx))
          .children(grid).children(links).children(nodes).when(Boolean(popover), el => el.child(popover))));
  }

  agentCard(profile) {
    const t = theme();
    const job = [...this.jobs].reverse().find(row => row.assigneeProfile === profile.id && !["completed", "failed"].includes(row.status));
    const role = this.role(profile);
    const live = this.live(profile);
    const status = job?.status === "needs-review" ? "done"
      : job?.status === "needs-input" || job?.status === "awaiting-approval" ? "blocked"
      : job ? "working" : live.status;
    const jobLabel = job?.status === "needs-review" ? "Đã gửi Leader tổng hợp"
      : job?.status === "needs-input" ? "Chờ Leader xử lý blocker"
      : job?.status === "awaiting-approval" ? "Leader đang chờ bạn xác nhận"
      : job?.task;
    const tone = status === "working" ? t.working : status === "blocked" ? t.blocked : status === "done" || status === "idle" ? t.done : t.dim;
    const limit5h = profile.usage?.fiveHour;
    const limitWeek = profile.usage?.week;
    return v_flex().id(`lane-${profile.id}`).px(9).py(7).gap(3).rounded(8).bg(status === "working" ? t.selected : t.surface).border_1().border_color(status === "working" ? t.working : t.border)
      .child(h_flex().items_center().gap(6)
        .child(div().size(6).flex_none().rounded(4).bg(tone))
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().w_full().truncate().text_size(10.5).child(profile.email || profile.id))
          .child(div().w_full().truncate().text_size(9.5).text_color(tone).child(job ? jobLabel : this.statusLabel(status))))
        .child(v_flex().w(42).flex_none().items_end().gap(1)
          .child(div().text_size(8.8).text_color(limitTone(t, limit5h)).child(`5H ${limit5h == null ? "—" : `${limit5h}%`}`))
          .child(div().text_size(8.8).text_color(limitTone(t, limitWeek)).child(`W  ${limitWeek == null ? "—" : `${limitWeek}%`}`)))
        .child(this.chip(role, role === "Leader" ? "accent" : "muted")))
      .when(job, el => el.child(div().truncate().text_size(9).text_color(t.working).child(`→ ${job.status} · ${job.stage ?? "execution"}`)));
  }

  liveActivityCard(profile) {
    const t = theme();
    return v_flex().id(`live-activity-${profile.id}`).p(10).gap(5).rounded(9).border_1().border_color(t.working).bg(t.selected)
      .child(h_flex().items_center().justify_between().gap(8)
        .child(v_flex().flex_1().min_w(0).gap(2)
          .child(div().truncate().text_size(11.5).font_semibold().child(`${this.profileName(profile.id)} đang làm`))
          .child(div().truncate().text_size(9.5).text_color(t.dim).child(`${this.role(profile)} · hoạt động trực tiếp từ terminal`)))
        .child(this.chip("Đang làm", "working")))
      .child(div().text_size(9.5).text_color(t.muted).child("Đang xử lý trực tiếp; chưa tạo job có cấu trúc."));
  }

  render() {
    const t = theme();
    this.frame = { terminals: terminals(), agents: agents() };
    const cfg = this.config();
    const dismissed = new Set((shared(DISMISSED_JOBS) ?? {})[this.spaceId()] ?? []);
    const active = [...this.jobs].filter(job => !["completed", "failed"].includes(job.status) && !dismissed.has(job.id)).reverse();
    const recent = [...this.jobs].filter(job => job.result || asArray(job.checkpoints).length).slice(-8).reverse();
    const orderedProfiles = [...this.profiles].sort((a, b) => {
      const order = { Leader: 0, Executor: 1, Agent: 2 };
      return order[this.role(a)] - order[this.role(b)] || String(a.createdAt ?? "").localeCompare(String(b.createdAt ?? ""));
    });
    const activeProfileIds = new Set(active.map(job => job.assigneeProfile).filter(Boolean));
    const workingProfiles = orderedProfiles.filter(profile => this.live(profile).status === "working");
    const untrackedWorking = workingProfiles.filter(profile => !activeProfileIds.has(profile.id));
    const waitingLeader = active.filter(job => job.status === "needs-input" || job.status === "needs-review").length;
    const waitingUser = active.filter(job => job.status === "awaiting-approval").length;
    const completed = this.jobs.filter(job => (job.status === "completed" || job.status === "needs-review") && !dismissed.has(job.id)).length;
    const runningCount = active.filter(job => ["queued", "working", "checking"].includes(job.status)).length + untrackedWorking.length;
    if (!this.selectedJobId && active.length) this.selectedJobId = active[0].id;

    const mailbox = [...this.mailbox].slice(-30).reverse();
    const feedbackColumn = v_flex().w(320).flex_none().h_full().min_h(0).gap(5)
      .child(h_flex().items_center().justify_between()
        .child(div().text_size(11).font_semibold().child("Mailbox · Bàn giao nội bộ"))
        .child(div().text_size(9.5).text_color(t.dim).child(`${mailbox.length} tin`)))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar()
        .children(mailbox.map(message => this.mailboxRow(message)))
        .when(!mailbox.length, el => el.children(recent.map(job => this.handoffRow(job))))
        .when(!mailbox.length && !recent.length, el => el.child(div().p(8).text_size(9.5).text_color(t.dim).child("Chưa có tin nhắn nội bộ."))));

    const stats = h_flex().flex_none().border_t(1).border_b(1).border_color(t.border)
      .child(this.stat("Đang chạy", runningCount, "working", "running"))
      .child(div().w(1).h_full().bg(t.border))
      .child(this.stat("Chờ Leader", waitingLeader, waitingLeader ? "accent" : "muted", "waiting-leader"))
      .child(div().w(1).h_full().bg(t.border))
      .child(this.stat("Chờ bạn", waitingUser, waitingUser ? "blocked" : "muted", "waiting-user"))
      .child(div().w(1).h_full().bg(t.border))
      .child(this.stat("Đã có kết quả", completed, "done", "result"));

    return v_flex().id("space-flow-board").size_full().min_h(0).p(12).gap(11).bg(t.canvas).text_color(t.foreground)
      .child(h_flex().items_center().justify_between()
        .child(v_flex().gap(2)
          .child(h_flex().items_center().gap(7)
            .child(div().text_size(16).font_semibold().child("Bảng điều hành Agent"))
            .child(this.chip("LIVE", workingProfiles.length ? "done" : "muted")))
          .child(div().text_size(10).text_color(t.dim).child(`${workingProfiles.length} agent đang hoạt động · Leader giao việc, worker thực thi, mailbox trả kết quả`)))
        .child(div().text_size(9).text_color(t.dim).child(this.spaceId())))
      .when(!cfg.workflowSetupConfirmed, el => el.child(div().px(10).py(8).rounded(8).border_1().border_color(t.blocked).text_size(10.5).text_color(t.blocked).child("Chưa chọn Leader và nhóm worker trong Thiết lập workflow.")))
      .when(Boolean(this.error), el => el.child(div().px(10).py(7).rounded(7).bg(t.raised).text_size(9.5).text_color(t.blocked).child(this.error)))
      .child(this.callGraph(active, orderedProfiles, workingProfiles))
      .child(h_flex().flex_1().min_h(400).items_start().gap(10)
        .child(this.taskBoard(this.jobs.filter(job => !dismissed.has(job.id)), orderedProfiles, untrackedWorking, waitingUser, this.mailbox.length))
        .when(this.showMailbox, el => el.child(feedbackColumn)));
  }
}
