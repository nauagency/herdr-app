import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, agents, run, openOverlay, theme, nextCommand, shared, setShared, layout, exec, appHome } from "herdr";

const labels = { working: "đang làm", "waiting-host": "chờ Host", blocked: "cần bạn", done: "xong", idle: "rảnh" };
const RECORDS = "space-manager.spaces.v1";

function records() { return shared(RECORDS) ?? []; }
function uid() { return `space-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`; }
function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}
function sidebarNarrow() { return (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160; }
function parseJsonOutput(stdout, fallback = []) {
  const clean = String(stdout ?? "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  return clean ? JSON.parse(clean) : fallback;
}

export default class SpaceManagerSpaces extends View {
  init(_props, cx) {
    this.creating = false;
    this.restoring = true;
    this.jobsBySpace = {};
    this.jobsLoading = false;
    if (!records().length && Object.keys(shared("space-manager.config.v1") ?? {}).length) {
      setShared(RECORDS, [{ id: uid(), runtimeId: "", name: "~" }]);
    }
    cx.spawn(async cx => {
      for (;;) {
        const command = await nextCommand();
        if (command === "new") this.createEmptySpace(cx);
        else if (command === "ask-delete") this.askDelete();
        else if (command === "delete-space") this.deleteSpace(cx);
        cx.notify();
      }
    });
    cx.timer.after(350, cx => this.restoreNext(cx));
    cx.timer.every(1500, cx => this.restoreNext(cx));
    this.refreshJobs(cx);
    cx.timer.every(4000, cx => this.refreshJobs(cx));
  }

  refreshJobs(cx) {
    if (this.jobsLoading) return;
    this.jobsLoading = true;
    cx.spawn(async cx => {
      const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
      const next = { ...this.jobsBySpace };
      await Promise.all(spaces().map(async space => {
        try {
          const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "list", space.id]);
          next[space.id] = parseJsonOutput(result.stdout);
        } catch { next[space.id] = next[space.id] ?? []; }
      }));
      this.jobsBySpace = next;
      this.jobsLoading = false;
      cx.notify();
    });
  }

  effectiveStatus(agent, spaceId) {
    const job = [...(this.jobsBySpace[spaceId] ?? [])].reverse().find(row => row.assignee === agent.address && !["completed", "failed"].includes(row.status));
    if (!job) return agent.status;
    if (job.status === "needs-review") return "done";
    if (job.status === "needs-input") return "waiting-host";
    if (job.status === "awaiting-approval") return "blocked";
    return "working";
  }

  restoreNext(cx) {
    if (this.creating) return;
    const current = spaces();
    const all = records();
    const live = new Set(current.map(s => s.id));
    const liveRecords = all.filter(r => live.has(r.runtimeId));
    const deduped = all.filter(r => live.has(r.runtimeId) || !liveRecords.some(x => x.name === r.name && (!x.folder || !r.folder || x.folder === r.folder)));
    if (deduped.length !== all.length) {
      setShared(RECORDS, deduped);
      cx.notify();
      return;
    }
    const missing = all.find(r => !live.has(r.runtimeId));
    if (!missing) {
      this.restoring = false;
      cx.notify();
      return;
    }
    const claimed = new Set(all.map(r => r.runtimeId).filter(Boolean));
    const existing = current.find(s => !claimed.has(s.id) && s.name === missing.name && (!missing.folder || s.folder === missing.folder));
    if (existing) {
      setShared(RECORDS, all.map(r => r.id === missing.id ? { ...r, runtimeId: existing.id, folder: existing.folder } : r));
      cx.notify();
      return;
    }
    this.restoring = true;
    this.createEmptySpace(cx, { recordId: missing.id, args: { name: missing.name, folder: missing.folder }, restoring: true });
  }

  saveRecord(created, recordId = null) {
    const all = records();
    const i = all.findIndex(r => r.id === recordId);
    const old = i >= 0 ? all[i] : {};
    const item = { ...old, id: recordId ?? uid(), runtimeId: created.id, name: created.name, folder: created.folder };
    const next = [...all];
    if (i >= 0) next[i] = item;
    else next.push(item);
    setShared(RECORDS, next);
  }

  syncRecords() {
    if (this.restoring || this.creating) return;
    const all = records();
    let changed = false;
    const next = [...all];
    for (const space of spaces()) {
      const i = next.findIndex(r => r.runtimeId === space.id);
      if (i < 0) {
        next.push({ id: uid(), runtimeId: space.id, name: space.name, folder: space.folder });
        changed = true;
      } else if (next[i].name !== space.name || next[i].folder !== space.folder) {
        next[i] = { ...next[i], name: space.name, folder: space.folder };
        changed = true;
      }
    }
    if (changed) setShared(RECORDS, next);
  }

  createEmptySpace(cx, pending = null) {
    if (this.creating) return;
    this.creating = true;
    const before = new Set(spaces().map(s => s.id));
    const queued = pending ?? shared("empty-space.pending-create") ?? {};
    const args = queued.args ?? queued;
    setShared("empty-space.pending-create", null);
    run("space.new", { ...args, argv: ["cmd.exe", "/d", "/q"] });
    const replace = (attempt, cx) => {
      const created = spaces().find(s => !before.has(s.id));
      if (!created) {
        if (attempt < 15) cx.timer.after(80, cx => replace(attempt + 1, cx));
        else { this.creating = false; this.restoring = false; cx.notify(); }
        return;
      }
      this.saveRecord(created, queued.recordId ?? null);
      const initial = created.tabs[0];
      run("tab.new", { space: created.id, name: "__space__", mod: "empty-space" });
      if (initial) cx.timer.after(80, () => run("tab.close", { id: initial.id, confirmed: true }));
      this.creating = false;
      if (queued.restoring) cx.timer.after(150, cx => this.restoreNext(cx));
      else { this.restoring = false; cx.notify(); }
    };
    cx.timer.after(80, cx => replace(0, cx));
  }

  requestNewSpace() {
    const current = spaces().find(s => s.active);
    setShared("empty-space.pending-create", { args: { folder: current?.folder } });
    run("space-manager-spaces.new");
  }

  openMenu(space) {
    setShared("space-manager.space-target", space.id);
    openOverlay({ mod: "space-menu", kind: "popup", width: 200, height: 150, props: { tab: "space", target: { id: space.id } } });
  }

  askDelete() {
    const id = shared("space-manager.space-target");
    const space = spaces().find(s => s.id === id);
    if (!space) return;
    openOverlay({ mod: "confirm", kind: "dialog", width: 430, height: 210, props: {
      title: `Xoá Space ${space.name}?`,
      detail: "Space sẽ bị xoá khỏi danh sách. Mọi agent và tab đang chạy trong Space này cũng sẽ dừng. Không thể hoàn tác.",
      command: { name: "space-manager-spaces.delete-space" },
    }});
  }

  deleteSpace(cx) {
    const id = shared("space-manager.space-target");
    if (!id) return;
    setShared(RECORDS, records().filter(r => r.runtimeId !== id));
    setShared("space-manager.space-target", null);
    run("space.close", { id, confirmed: true });
    cx.notify();
  }

  render() {
    this.syncRecords();
    const t = theme();
    const allAgents = agents();
    if (sidebarNarrow()) {
      return v_flex().id("space-manager-spaces-rail").size_full().min_h(0).px(5).py(6).gap(5).items_center().bg(t.chrome)
        .child(div().id("new-space-rail").w(32).h(32).rounded(8).items_center().justify_center().text_size(18).text_color(t.foreground)
          .cursor_pointer().hover(s => s.bg(t.raised)).on_click(() => this.requestNewSpace()).child("+"))
        .child(v_flex().flex_1().min_h(0).w_full().items_center().overflow_y_scrollbar().gap(5).children(spaces().map(space => {
          const list = allAgents.filter(a => a.space === space.id);
          const blocked = list.some(a => this.effectiveStatus(a, space.id) === "blocked");
          return div().id(`space-rail-${space.id}`).w(32).h(32).rounded(9).items_center().justify_center()
            .bg(space.active ? t.selected : t.chrome).text_color(blocked ? t.blocked : (t[space.status] ?? t.dim))
            .cursor_pointer().hover(s => s.bg(t.hover))
            .on_mouse_down("left", (e, cx) => { cx.stop_propagation(); run("space.select", { id: space.id }); })
            .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(space); })
            .child("●");
        })));
    }
    return v_flex().id("space-manager-spaces").size_full().min_h(0).p(10).gap(6).bg(t.chrome)
      .child(h_flex().h(28).items_center().justify_between()
        .child(div().text_size(11).font_semibold().text_color(t.muted).child("SPACES"))
        .child(div().id("new-space").w(26).h(26).rounded(7).items_center().justify_center().text_size(18).text_color(t.foreground)
          .cursor_pointer().hover(s => s.bg(t.raised)).on_click(() => this.requestNewSpace()).child("+")))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().gap(4).children(spaces().map(space => {
        const list = allAgents.filter(a => a.space === space.id);
        const counts = Object.fromEntries(["working", "waiting-host", "blocked", "done", "idle"].map(status => [status, list.filter(a => this.effectiveStatus(a, space.id) === status).length]));
        const summary = Object.entries(counts).filter(([, n]) => n > 0).map(([s, n]) => `${n} ${labels[s]}`).join(" · ") || "Chưa có agent đang chạy";
        return v_flex().id(`space-${space.id}`).min_h(50).px(9).py(7).gap(3).rounded(9)
          .bg(space.active ? t.selected : t.chrome).cursor_pointer().hover(s => s.bg(t.hover))
          .on_mouse_down("left", (e, cx) => {
            cx.stop_propagation();
            if (e.click_count === 2) run("space.rename", { id: space.id });
            else run("space.select", { id: space.id });
          })
          .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(space); })
          .child(h_flex().items_center().gap(7)
            .child(div().text_color(t[space.status] ?? t.dim).child(space.status ? "●" : "○"))
            .child(div().flex_1().min_w(0).truncate().text_size(12.8).font_medium().text_color(t.foreground).child(space.name)))
          .child(div().pl(15).truncate().text_size(10.5).text_color(counts.blocked ? t.blocked : t.dim).child(summary));
      })));
  }
}
