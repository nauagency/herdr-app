import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, agents, terminals, knownAgents, run, openOverlay, theme, shared, setShared, appHome, exec, hc, nextCommand, notify, setAgentOrder, layout } from "herdr";
import * as fs from "fs/promises";

const CONFIG = "space-manager.config.v1";
const LEADER_RESPONSE_POLICY = `COMMUNICATION POLICY: Trả lời người dùng bằng tiếng Việt, kết luận trước, ngắn gọn, dễ hiểu và dùng từ phổ thông. Chỉ nêu kết quả, trạng thái, thay đổi quan trọng hoặc đúng quyết định còn thiếu. Không chép prompt, policy, log, lệnh, checkpoint, evidence ID, job ID hay quy trình nội bộ trừ khi người dùng hỏi.`;
const LEADER_ROLE_POLICY = `LEADER MODEL: Bạn là đầu mối duy nhất giữa người dùng và đội. Hãy hiểu mục tiêu, chia thành các việc độc lập, giao cho worker phù hợp, rồi kết thúc lượt và chờ mailbox chủ động đánh thức; tuyệt đối không poll terminal, không lặp hc read/hc wait và không phát tiến độ vụn. Worker chỉ nhận ngữ cảnh của đúng việc. Khi mọi việc con đã hoàn tất, bạn tự đối chiếu các kết quả, xử lý mâu thuẫn và trả người dùng một kết luận tổng hợp. Với nghiên cứu chỉ đọc, bạn không tự đọc repo thay worker. Với triển khai code, bạn xác định tiêu chí đạt, yêu cầu kiểm tra cục bộ và review bằng chứng trước khi xin duyệt merge/deploy. Worker bị chặn phải báo lại bạn; chỉ bạn mới hỏi người dùng. Không có Host AI trung gian.`;
const FLOW_PROFILES = "space-flow.profiles.v1";
const FLASH = ["gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low"];

function parseJsonOutput(stdout, fallback = []) {
  const clean = String(stdout ?? "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  return clean ? JSON.parse(clean) : fallback;
}

function activeSpace() { return spaces().find(s => s.active); }
function configs() { return shared(CONFIG) ?? {}; }
function findLayout(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = findLayout(child, id);
    if (found) return found;
  }
  return null;
}
function sidebarNarrow() { return (findLayout(layout(), "sidebar")?.size?.px ?? Infinity) < 160; }
function showAgentTerminal(address) {
  if (!address) return;
  // Login terminals can belong to an older hidden tab. Opening a peek is
  // independent of that tab, while pane.focus would silently focus the hidden
  // pane and leave the current dashboard unchanged.
  run("terminal.peek", { terminal: address });
}
function statusLabel(status) {
  return { working: "Đang làm", blocked: "Cần bạn", done: "Đã xong", idle: "Sẵn sàng" }[status] ?? "Sẵn sàng";
}
function limitTone(t, value) {
  if (value == null) return t.dim;
  if (value <= 10) return "#f05d6a";
  if (value <= 35) return t.done;
  if (value >= 75) return "#45c97a";
  return t.working;
}
function normalizedModel(value) { return String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }
function asArray(value) { return value == null ? [] : Array.isArray(value) ? value : [value]; }
function profileProvider(profile) { return String(profile.provider || profile.agentFamily || profile.agent || "").toLowerCase(); }
function quotaFloor(profile) {
  const values = [profile?.usage?.fiveHour, profile?.usage?.week]
    .filter(value => value != null && Number.isFinite(Number(value)))
    .map(Number);
  return values.length ? Math.min(...values) : null;
}
function runtimeModelFromScreen(text) {
  const gemini = String(text).match(/Gemini\s+([0-9.]+)\s+(Flash|Argon)(?:\s*[·(]\s*(Low|Medium|High|XHigh|Max)\)?)/i);
  if (gemini) {
    const effort = gemini[3].toLowerCase();
    return { id: `gemini-${gemini[1]}-${gemini[2].toLowerCase()}-${effort}`, label: `Gemini ${gemini[1]} ${gemini[2]} · ${gemini[3]}` };
  }
  const codex = String(text).match(/\b(GPT[-\s][A-Za-z0-9._-]+)\s*[· ]\s*(low|medium|high|xhigh|max)\b/i);
  if (codex) return { id: normalizedModel(codex[1]), effort: codex[2].toLowerCase(), label: `${codex[1]} · ${codex[2]}` };
  return null;
}

export default class SpaceManager extends View {
  init(_props, cx) {
    this.profiles = {};
    this.allProfiles = [];
    this.jobs = [];
    this.installed = [];
    this.flashAvailable = false;
    this.loading = false;
    this.pendingDelete = null;
    this.pendingRestart = null;
    this.pendingPermissionRestart = null;
    this.pendingApproval = null;
    this.leadFallbackWarnings = new Set();
    this.runtimeModels = {};
    this.refresh(cx);
    cx.timer.every(5000, cx => this.refresh(cx));
    cx.spawn(async cx => {
      for (;;) {
        const command = await nextCommand();
        if (command === "delete" && this.pendingDelete) await this.deletePending(cx);
        else if (command === "restart-manager" && this.pendingRestart) await this.restartManager(cx);
        else if (command === "restart-permissions" && this.pendingPermissionRestart) await this.restartPermissionTargets(cx);
        else if (command === "approve-job" && this.pendingApproval) await this.approvePendingJob(cx);
        else if (command === "apply-workflow") { const space = activeSpace(); if (space) await this.applyWorkflowPolicy(space); }
        else if (command === "start") { const space = activeSpace(); if (space && !this.managerTerminal(space)) this.startManager(space); }
        cx.notify();
      }
    });
  }

  config(space) {
    const all = configs();
    const saved = all[space?.id] ?? {};
    const flashHost = this.installed.find(a => a.installed && (a.key === "antigravity" || /antigravity|gemini/i.test(a.name)));
    const fallback = this.installed.find(a => a.installed);
    return {
      hostKey: saved.hostKey ?? (this.flashAvailable && flashHost ? flashHost.key : fallback?.key ?? ""),
      model: saved.model ?? (this.flashAvailable && flashHost ? FLASH[0] : "default"),
      effort: saved.effort ?? "high",
      profileId: saved.profileId ?? "",
      workflowEnabled: saved.workflowEnabled ?? true,
      workflowSetupConfirmed: saved.workflowSetupConfirmed ?? false,
      leadProfileId: saved.leadProfileId ?? "",
      executorProfileIds: saved.executorProfileIds ?? [],
      maxReworkRounds: saved.maxReworkRounds ?? 3,
      sameErrorLimit: saved.sameErrorLimit ?? 2,
      maxExecutorBackups: saved.maxExecutorBackups ?? 2,
      autoResumeLimit: saved.autoResumeLimit ?? 1,
      minQuotaPercent: saved.minQuotaPercent ?? 10,
      approvalMode: saved.approvalMode ?? "auto",
      agentStatusFilter: saved.agentStatusFilter ?? "",
      requireApprovalForMerge: saved.requireApprovalForMerge ?? true,
      forbidProviderSwitch: saved.forbidProviderSwitch ?? true,
      orchestrationMode: saved.orchestrationMode ?? "control-plane-v2",
    };
  }

  save(space, patch) {
    const all = configs();
    setShared(CONFIG, { ...all, [space.id]: { ...this.config(space), ...patch } });
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    const space = activeSpace();
    cx.spawn(async cx => {
      try {
        this.installed = await knownAgents({ on: space?.machine });
        if (!space?.machine) {
          try {
            const result = await exec("agy", ["models"], { timeout: 20000 });
            this.flashAvailable = result.code === 0 && result.stdout.includes(FLASH[0]);
          } catch { this.flashAvailable = false; }
        }
        if (space && !space.machine) {
          const helper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
          const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "list-all", ""]);
          this.allProfiles = parseJsonOutput(result.stdout);
          this.profiles[space.id] = this.allProfiles.filter(p => p.spaceId === space.id);
          const flowProfiles = shared(FLOW_PROFILES) ?? {};
          setShared(FLOW_PROFILES, { ...flowProfiles, [space.id]: this.profiles[space.id] });
          await this.ensureDefaultWorkflow(space);
          await this.ensureLeaderMode(space);
          await this.reconcileLeaderLabels(space);
          await this.ensureLeadFallback(space);
          const jobsHelper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
          await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "recover", space.id]);
          // The control plane owns assignment. A request stays durable even
          // when every worker is busy, and the next refresh assigns queued
          // work to an eligible idle profile without creating a duplicate job.
          await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "schedule", space.id]);
          const jobsResult = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", jobsHelper, "list", space.id]);
          this.jobs = parseJsonOutput(jobsResult.stdout);
          const managerTerminal = this.managerTerminal(space);
          if (managerTerminal) {
            try {
              const screen = await exec("hc", ["read", managerTerminal.address, "--lines", "80"], { timeout: 5000 });
              const parsed = runtimeModelFromScreen(screen.stdout);
              if (parsed) this.runtimeModels[managerTerminal.address] = parsed;
            } catch {}
          }
          const saved = configs()[space.id];
          if (saved?.profileId && !this.allProfiles.some(p => p.id === saved.profileId && p.authenticated)) {
            this.save(space, { profileId: "" });
          }
        }
      } catch {}
      this.loading = false;
      cx.notify();
    });
  }

  async ensureDefaultWorkflow(space) {
    const saved = configs()[space.id] ?? {};
    if (saved.workflowSetupConfirmed) return;
    const ordered = [...(this.profiles[space.id] ?? [])]
      .filter(profile => profile.authenticated)
      .sort((a, b) => (Date.parse(a.createdAt ?? "") || Number.MAX_SAFE_INTEGER) - (Date.parse(b.createdAt ?? "") || Number.MAX_SAFE_INTEGER));
    const hostProfileId = saved.profileId ?? "";
    const lead = ordered.find(profile => profile.id !== hostProfileId && /codex|claude/.test(profileProvider(profile)));
    const executors = ordered.filter(profile => profile.id !== hostProfileId && profile.id !== lead?.id && /antigravity|gemini/.test(profileProvider(profile)));
    if (!lead || !executors.length) return;
    this.save(space, {
      workflowEnabled: true,
      workflowSetupConfirmed: true,
      leadProfileId: lead.id,
      executorProfileIds: executors.map(profile => profile.id),
    });
    const helper = `${appHome()}/mods/space-manager-hostflow/workflow-policy.ps1`;
    await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "set", space.id, lead.id, executors.map(profile => profile.id).join(","), String(space.folder ?? "")]);
    if (this.managerTerminal(space)) await this.applyWorkflowPolicy(space);
    notify({ title: "Đã chọn workflow mặc định", body: `${lead.email || lead.id} làm Leader · ${executors.length} Gemini thực thi. Bạn có thể đổi trong Workflow.`, level: "info" });
  }

  async ensureLeaderMode(space) {
    const cfg = this.config(space);
    if (!cfg.workflowSetupConfirmed || !cfg.leadProfileId) return;
    const leader = (this.profiles[space.id] ?? []).find(profile => profile.id === cfg.leadProfileId && profile.authenticated);
    if (!leader) return;
    const provider = profileProvider(leader);
    const hostKey = provider.includes("claude") ? "claude" : provider.includes("codex") ? "codex" : provider.includes("antigravity") || provider.includes("gemini") ? "antigravity" : cfg.hostKey;
    const needsMigration = cfg.profileId !== leader.id || cfg.orchestrationMode !== "control-plane-v2";
    if (!needsMigration) return;
    const oldManager = this.managerTerminal(space);
    const liveLeader = terminals().find(t => t.labels?.["herdr.space"] === space.id && t.labels?.["herdr.profile"] === leader.id);
    this.save(space, { profileId: leader.id, hostKey, model: "default", effort: provider.includes("gemini") ? "high" : "medium", orchestrationMode: "control-plane-v2" });
    if (oldManager && oldManager.address !== liveLeader?.address) {
      try { await hc(["kill", oldManager.address]); } catch {}
    }
    if (liveLeader) {
      try { await hc(["label", liveLeader.address, `herdr.space=${space.id}`, "herdr.role=manager"]); } catch {}
    }
    await this.applyWorkflowPolicy(space);
    notify({ title: "Đã chuyển sang Leader trực tiếp", body: `${leader.email || leader.id} nhận yêu cầu, giao việc và tổng hợp; không còn Host AI trung gian.`, level: "info" });
  }

  async reconcileLeaderLabels(space) {
    const cfg = this.config(space);
    if (!cfg.profileId) return;
    const inSpace = terminals().filter(t => t.labels?.["herdr.space"] === space.id);
    const selected = inSpace.find(t => t.labels?.["herdr.profile"] === cfg.profileId);
    const selectedIsLive = Boolean(selected && agents().some(agent => agent.address === selected.address));
    for (const terminal of inSpace) {
      const shouldLead = selectedIsLive && terminal.address === selected.address;
      const currentRole = terminal.labels?.["herdr.role"];
      if (shouldLead && currentRole !== "manager") {
        try { await hc(["label", terminal.address, "herdr.role=manager"]); } catch {}
      } else if (!shouldLead && currentRole === "manager") {
        try { await hc(["label", terminal.address, "herdr.role=worker"]); } catch {}
      }
    }
  }

  async ensureLeadFallback(space) {
    const cfg = this.config(space);
    if (!cfg.workflowSetupConfirmed || !cfg.leadProfileId) return;
    const profiles = this.profiles[space.id] ?? [];
    const current = profiles.find(profile => profile.id === cfg.leadProfileId);
    const currentQuota = quotaFloor(current);
    if (current?.authenticated && (currentQuota == null || currentQuota > cfg.minQuotaPercent)) {
      this.leadFallbackWarnings.delete(space.id);
      return;
    }

    const provider = profileProvider(current);
    const replacement = profiles
      .filter(profile => profile.id !== current.id
        && profile.id !== cfg.profileId
        && profile.authenticated
        && profileProvider(profile) === provider
        && /codex|claude/.test(profileProvider(profile)))
      .map(profile => ({ profile, quota: quotaFloor(profile) }))
      .filter(row => row.quota == null || row.quota > cfg.minQuotaPercent)
      .sort((a, b) => {
        const scoreA = a.quota == null ? 50 : a.quota;
        const scoreB = b.quota == null ? 50 : b.quota;
        return scoreB - scoreA || (Date.parse(a.profile.createdAt ?? "") || Number.MAX_SAFE_INTEGER) - (Date.parse(b.profile.createdAt ?? "") || Number.MAX_SAFE_INTEGER);
      })[0]?.profile;

    if (!replacement) {
      if (!this.leadFallbackWarnings.has(space.id)) {
        this.leadFallbackWarnings.add(space.id);
        notify({ title: "Không còn Leader dự phòng", body: `Các ${provider || "Codex/Claude"} trong Space đều hết quota, đã đăng xuất hoặc chưa sẵn sàng.`, level: "warning" });
      }
      return;
    }

    this.leadFallbackWarnings.delete(space.id);
    this.save(space, { leadProfileId: replacement.id, profileId: replacement.id });
    const helper = `${appHome()}/mods/space-manager-hostflow/workflow-policy.ps1`;
    await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "set", space.id, replacement.id, cfg.executorProfileIds.join(","), String(space.folder ?? "")]);
    const manager = this.managerTerminal(space);
    if (manager) {
      try {
        await hc(["send", manager.address, `LEAD FALLBACK: ${current?.id || cfg.leadProfileId} ${current?.authenticated ? `còn ${currentQuota}% quota` : "đã đăng xuất"} nên đã được thay bằng ${replacement.id}. Tiếp tục cùng yêu cầu/job hiện tại, không tạo job trùng và chỉ dùng agent trong Space này.`]);
      } catch {}
      await this.applyWorkflowPolicy(space);
    }
    notify({ title: "Đã tự chuyển Leader", body: `${current?.email || current?.id || cfg.leadProfileId} (${current?.authenticated ? `${currentQuota}%` : "đã đăng xuất"}) → ${replacement.email || replacement.id} (${quotaFloor(replacement) ?? "chưa rõ"}%).`, level: "info" });
  }

  managerTerminal(space) {
    const cfg = this.config(space);
    const inSpace = terminals().filter(t => t.labels?.["herdr.space"] === space.id);
    // Once a Leader profile is selected, never fall back to an older terminal
    // that merely still carries herdr.role=manager. That stale label was why a
    // Codex Leader row opened the previous Antigravity Host.
    if (cfg.profileId) return inSpace.find(t => t.labels?.["herdr.profile"] === cfg.profileId) ?? null;
    return inSpace.find(t => t.labels?.["herdr.role"] === "manager") ?? null;
  }

  managerAgent(space) {
    const terminal = this.managerTerminal(space);
    if (terminal) return agents().find(a => a.address === terminal.address) ?? null;
    if (this.config(space).profileId) return null;
    return agents().find(a => a.space === space.id && ["Manager", "Leader"].includes(a.tab_name)) ?? null;
  }

  host(space) {
    const key = this.config(space).hostKey;
    return this.installed.find(a => a.key === key && a.installed) ?? this.installed.find(a => a.installed);
  }

  signedInProfile(space, cfg, managerTerminal) {
    const selected = this.allProfiles.find(p => p.id === cfg.profileId && p.authenticated);
    if (selected) return selected;
    const liveProfileId = managerTerminal?.labels?.["herdr.profile"];
    const live = this.allProfiles.find(p => p.id === liveProfileId && p.authenticated);
    if (live) return live;
    return null;
  }

  openHostPicker(space, mode = "accounts") {
    openOverlay({ mod: "host-picker", kind: "popup", width: 360, height: 520, props: { spaceId: space.id, machine: space.machine, mode } });
  }

  cycleHost(space) {
    const choices = this.installed.filter(a => a.installed);
    if (!choices.length) return;
    const current = choices.findIndex(a => a.key === this.config(space).hostKey);
    const next = choices[(current + 1 + choices.length) % choices.length];
    const flashHost = next.key === "antigravity" || /antigravity|gemini/i.test(next.name);
    this.save(space, { hostKey: next.key, model: flashHost && this.flashAvailable ? FLASH[0] : "default" });
  }

  cycleModel(space) {
    const host = this.host(space);
    const supportsFlash = this.flashAvailable && (host?.key === "antigravity" || /antigravity|gemini/i.test(host?.name ?? ""));
    const choices = supportsFlash ? [...FLASH, "default"] : ["default"];
    const i = choices.indexOf(this.config(space).model);
    this.save(space, { model: choices[(i + 1) % choices.length] });
  }

  openModelPicker(space) {
    const cfg = this.config(space);
    const mod = cfg.hostKey === "codex" ? "codex-model-picker" : cfg.hostKey === "claude" ? "claude-model-picker" : "manager-model-picker";
    openOverlay({ mod, kind: "popup", width: 370, height: 490, props: { spaceId: space.id, model: cfg.model, effort: cfg.effort, profileId: cfg.profileId, hostKey: cfg.hostKey } });
  }

  openWorkflowSettings(space) {
    openOverlay({ mod: "workflow-settings", kind: "popup", width: 500, height: 640, props: { spaceId: space.id, folder: space.folder } });
  }

  openPermissionSettings(space) {
    openOverlay({ mod: "space-permissions", kind: "popup", width: 450, height: 330, props: { spaceId: space.id } });
  }

  async saveHostPolicy(space, text) {
    const dir = `${appHome()}/data/space-manager-hostflow`;
    await fs.mkdir(dir, { recursive: true });
    const path = `${dir}/${space.id}-host-policy.txt`;
    await fs.writeFile(path, text, "utf8");
    return path;
  }

  async applyWorkflowPolicy(space) {
    const cfg = this.config(space);
    if (!cfg.workflowSetupConfirmed) return;
    const terminal = this.managerTerminal(space);
    if (!terminal) { this.startManager(space); return; }
    const jobsHelper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
    const update = `WORKFLOW POLICY UPDATE. You are the single Leader for Space ${space.id}; there is no separate Host. Allowed worker profiles=[${cfg.executorProfileIds.join(", ")}]. ${LEADER_ROLE_POLICY} Independent jobs may run in parallel. Create each child job with ${jobsHelper} route-dispatch <spaceId> <terminal> <fast-path|leader-first|ask-user> '<short reason>' <task>. After dispatch, end the turn and wait for mailbox delivery. Do not inspect worker terminals. Research jobs finish when all related children report and you synthesize once. Implementation jobs additionally require local gate, evidence and review before user approval. Retry the same job rather than creating duplicates; stop automatic retry after ${cfg.maxExecutorBackups} backups or ${cfg.sameErrorLimit} repeated identical failures. Use only the existing allowed worker profiles; never create an agent or internal subagent. Never switch provider, leave this Space, use paid APIs, touch secrets, merge, deploy or delete data without the user's explicit direction. When your final answer accepts one or more worker results, record the concise reply and close those exact jobs in one idempotent transaction with ${jobsHelper} complete-message ${space.id} <stable-key> <job-id[,job-id...]> <reply>. Use a generic leader.message only for conversation that closes no job. Never close a job merely because any Leader message exists. ${LEADER_RESPONSE_POLICY} Reply only that the Leader workflow is active.`;
    try {
      const path = await this.saveHostPolicy(space, update);
      await hc(["send", terminal.address, `Workflow của Space vừa được cập nhật. Hãy đọc và áp dụng file "${path}"; không chép nội dung file ra terminal. Chỉ xác nhận ngắn gọn.`]);
    }
    catch { notify({ title: "Đã lưu workflow", body: "Leader hiện chưa nhận được policy; khởi động lại Leader để áp dụng.", level: "warning" }); }
  }

  startManager(space, forceStart = false) {
    const host = this.host(space);
    if (!host) {
      notify({ title: "Chưa có Leader", body: "Hãy chọn một agent Leader trước.", level: "warning" });
      return;
    }
    const cfg = this.config(space);
    if (!cfg.workflowSetupConfirmed) {
      this.openWorkflowSettings(space);
      notify({ title: "Thiết lập workflow lần đầu", body: "Chọn Leader và các worker được phép nhận việc trong Space này.", level: "info" });
      return;
    }
    const jobsHelper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
    const executorIds = cfg.executorProfileIds.join(", ");
    const task = `Bạn là Leader duy nhất của Space "${space.name}" (${space.id}) và là agent người dùng trao đổi trực tiếp. Không có Host AI trung gian. Worker được phép=[${executorIds}]. ${LEADER_ROLE_POLICY} Dùng "${jobsHelper}" route-dispatch ${space.id} <terminal> <fast-path|leader-first|ask-user> '<lý do ngắn>' <task> để tạo từng việc con. Giao tất cả việc độc lập trước, sau đó kết thúc lượt và chờ kết quả được gửi về; không đọc/poll terminal. Với nghiên cứu nhiều repo, mỗi worker đọc một nguồn rồi bạn tổng hợp một lần. Với triển khai, đặt tiêu chí đạt, yêu cầu worktree riêng, checkpoint/evidence, gate cục bộ và review trước khi xin duyệt. Backup chỉ dùng agent đã có trong cùng Space, giữ nguyên jobId/worktree/checkpoint và tối đa ${cfg.maxExecutorBackups} lần. Không tạo agent hay internal subagent, không đổi provider, không dùng API trả phí, không rời Space, không làm trên main, không đụng secret/.env, không tự merge/deploy/xoá dữ liệu. Khi câu trả lời cuối chấp nhận kết quả worker, ghi câu trả lời và đóng đúng các job trong một giao dịch bằng "${jobsHelper}" complete-message ${space.id} <khóa-ổn-định> <job-id[,job-id...]> <nội dung ngắn gọn>. Chỉ dùng message leader.message cho trao đổi không đóng job; không được suy đoán đóng job từ một tin nhắn chung. ${LEADER_RESPONSE_POLICY}`;
    const selectedLive = !forceStart && cfg.profileId ? terminals().find(t => t.labels?.["herdr.profile"] === cfg.profileId) : null;
    if (selectedLive) {
      const requested = selectedLive.labels?.["herdr.model.requested"];
      const observed = this.runtimeModels[selectedLive.address]?.id;
      const configured = normalizedModel(cfg.model);
      const actual = normalizedModel(observed || requested);
      if (cfg.model !== "default" && actual && actual !== configured) {
        this.askManagerRestart(space, selectedLive, this.runtimeModels[selectedLive.address]?.label ?? requested);
        return;
      }
      (async () => {
        await hc(["label", selectedLive.address, `herdr.space=${space.id}`, "herdr.role=manager"]);
        const path = await this.saveHostPolicy(space, task);
        await hc(["send", selectedLive.address, `Nạp lại hướng dẫn Leader từ file "${path}" và tiếp tục công việc hiện tại. Không chép nội dung file ra terminal; chỉ xác nhận ngắn gọn.`]);
        run("pane.focus", { terminal: selectedLive.address });
      })().catch(e => notify({ title: "Chưa bật được Leader", body: String(e.message ?? e), level: "warning" }));
      return;
    }
    const argv = [...host.run];
    if (cfg.model !== "default" && host.key === "codex") {
      argv.push("--model", cfg.model, "-c", `model_reasoning_effort=${JSON.stringify(cfg.effort)}`);
    } else if (cfg.model !== "default" && host.key === "claude") {
      argv.push("--model", cfg.model, "--effort", cfg.effort);
    } else if (cfg.model !== "default" && (host.key === "antigravity" || /antigravity|gemini/i.test(host.name))) {
      argv.push("--model", cfg.model, "--mode", "auto");
    }
    if (host.key === "antigravity" || /antigravity|gemini/i.test(host.name)) {
      argv.push("--prompt-interactive");
    }
    const isolated = space.machine ? argv : [
      "powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      `${appHome()}/mods/persistent-new-menu/run-agent-isolated.ps1`, host.key, space.id, "manager", cfg.profileId || "__new__", ...argv,
    ];
    (async () => {
      const path = space.machine ? null : await this.saveHostPolicy(space, task);
      const launchTask = path
        ? `Bạn là Leader duy nhất của Space này. Đọc và áp dụng toàn bộ hướng dẫn trong file "${path}". Không chép nội dung file ra terminal; chỉ xác nhận ngắn gọn rồi sẵn sàng nhận việc.`
        : task;
      run("tab.new", { name: "Leader", space: space.id, folder: space.folder, argv: isolated, task: launchTask });
    })().catch(e => notify({ title: "Chưa bật được Leader", body: String(e.message ?? e), level: "warning" }));
  }

  askManagerRestart(space, terminal, actualLabel = "thiết lập hiện tại", kind = "model") {
    this.pendingRestart = { spaceId: space.id, address: terminal?.address, profileId: this.config(space).profileId };
    openOverlay({ mod: "confirm", kind: "dialog", width: 450, height: 220, props: {
      title: `Khởi động lại Leader để áp dụng ${kind === "permission" ? "quyền" : "model"}?`,
      detail: `Leader đang chạy ${actualLabel}, khác với thiết lập của Space. Hồ sơ đăng nhập được giữ nguyên.`,
      command: { name: "space-manager-hostflow.restart-manager" },
    }});
  }

  async restartManager(cx) {
    const pending = this.pendingRestart;
    this.pendingRestart = null;
    const space = spaces().find(s => s.id === pending?.spaceId);
    if (!space) return;
    try {
      if (pending.address) {
        await hc(["kill", pending.address]);
        try { await hc(["wait", pending.address]); } catch {}
      }
      cx.timer.after(450, () => this.startManager(space, true));
    } catch (e) {
      notify({ title: "Chưa khởi động lại được Leader", body: String(e.message ?? e), level: "warning" });
    }
  }

  askPermissionRestart(space, targets) {
    this.pendingPermissionRestart = { spaceId: space.id, targets: targets.map(terminal => ({
      address: terminal.address,
      profileId: terminal.labels?.["herdr.profile"],
      role: terminal.labels?.["herdr.role"] ?? "worker",
      tabId: terminal.labels?.["herdr.tab"],
    })) };
    openOverlay({ mod: "confirm", kind: "dialog", width: 470, height: 225, props: {
      title: `Áp dụng quyền cho ${targets.length} agent?`,
      detail: "Các agent đang dùng quyền cũ sẽ được khởi động lại trong đúng hồ sơ. Tab cũ được đóng; đăng nhập vẫn giữ nguyên.",
      command: { name: "space-manager-hostflow.restart-permissions" },
    }});
  }

  async restartPermissionTargets(cx) {
    const pending = this.pendingPermissionRestart;
    this.pendingPermissionRestart = null;
    const space = spaces().find(row => row.id === pending?.spaceId);
    if (!space) return;
    let restarted = 0;
    for (const target of pending.targets) {
      const terminal = terminals().find(row => row.address === target.address) ?? { address: target.address, labels: { "herdr.tab": target.tabId } };
      if (target.role === "manager") {
        try {
          await hc(["kill", target.address]);
          try { await hc(["wait", target.address]); } catch {}
          this.startManager(space, true);
          restarted++;
        } catch {}
        continue;
      }
      const profile = this.allProfiles.find(row => row.id === target.profileId);
      if (!profile) continue;
      await this.restartProfileNow(profile, false, space, terminal);
      restarted++;
    }
    const manager = this.managerTerminal(space);
    if (manager && restarted > 0) {
      try {
        await hc(["send", manager.address, `PERMISSION RESTART: ${restarted} agent vừa được mở lại với quyền ${this.config(space).approvalMode}. Chạy recover rồi list; tiếp tục các job hiện tại theo profileId/checkpoint và cập nhật terminal assignee mới, không tạo job trùng.`]);
      } catch {}
    }
    notify({ title: "Đã áp dụng quyền của Space", body: `${restarted} agent đã được mở lại với quyền ${this.config(space).approvalMode}.`, level: "info" });
    cx.notify();
  }

  async restartProfileNow(profile, isManager, space, liveTerminal) {
    const host = this.installed.find(a => a.installed && a.key === (profile.provider || profile.agentFamily || profile.agent));
    if (!host) throw new Error(`Không tìm thấy ${profile.provider || profile.agentFamily || profile.agent}`);
    if (liveTerminal?.address) {
      await hc(["kill", liveTerminal.address]);
      try { await hc(["wait", liveTerminal.address]); } catch {}
    }
    const savedArgs = Array.isArray(profile.arguments)
      ? profile.arguments.filter(value => typeof value === "string" && value.trim().length > 0)
      : [];
    const args = savedArgs.length ? savedArgs : host.run.slice(1).filter(value => typeof value === "string" && value.trim().length > 0);
    const command = profile.command || host.run[0];
    const isolated = ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
      `${appHome()}/mods/persistent-new-menu/run-agent-isolated.ps1`, host.key, space.id, isManager ? "manager" : "worker", profile.id, command, ...args];
    run("tab.new", { name: isManager ? "Leader" : host.name, space: space.id, folder: space.folder, argv: isolated });
  }

  revealProfileTerminal(profileId, previousAddress, attempt, cx) {
    const terminal = [...terminals()].reverse().find(row => row.address !== previousAddress && row.labels?.["herdr.profile"] === profileId);
    if (terminal) {
      showAgentTerminal(terminal.address);
      return;
    }
    if (attempt < 30) cx.timer.after(100, innerCx => this.revealProfileTerminal(profileId, previousAddress, attempt + 1, innerCx));
  }

  restartProfile(profile, isManager, space, liveTerminal, cx) {
    const host = this.installed.find(a => a.installed && a.key === (profile.provider || profile.agentFamily || profile.agent));
    if (!host) {
      notify({ title: "Không tìm thấy agent", body: profile.provider || profile.agentFamily || profile.agent, level: "warning" });
      return;
    }
    cx.spawn(async cx => {
      try {
        await this.restartProfileNow(profile, isManager, space, liveTerminal);
        cx.timer.after(80, innerCx => this.revealProfileTerminal(profile.id, liveTerminal?.address, 0, innerCx));
      } catch (e) {
        notify({ title: "Chưa khởi động lại được agent", body: String(e.message ?? e), level: "warning" });
      }
      cx.notify();
    });
  }

  askDelete(profile) {
    this.pendingDelete = profile;
    openOverlay({ mod: "confirm", kind: "dialog", width: 430, height: 210, props: {
      title: `Xoá vĩnh viễn ${profile.id}?`,
      detail: "Toàn bộ đăng nhập, lịch sử và dữ liệu riêng của hồ sơ này sẽ bị xoá và không thể hoàn tác.",
      command: { name: "space-manager-hostflow.delete" },
    }});
  }

  async deletePending(cx) {
    const profile = this.pendingDelete;
    this.pendingDelete = null;
    const live = terminals().find(t => t.labels?.["herdr.profile"] === profile.id);
    if (live) { try { await hc(["kill", live.address]); } catch {} }
    const helper = `${appHome()}/mods/space-manager-hostflow/profile-store.ps1`;
    try {
      const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "delete", profile.id]);
      if (result.code !== 0) throw new Error(result.stderr);
      const space = activeSpace();
      if (space) this.profiles[space.id] = (this.profiles[space.id] ?? []).filter(p => p.id !== profile.id);
    } catch (e) { notify({ title: "Chưa xoá được hồ sơ", body: String(e.message ?? e), level: "warning" }); }
    cx.notify();
  }

  pill(id, label, action, primary = false) {
    const t = theme();
    return h_flex().id(id).h(28).px(9).items_center().rounded(7).border_1().border_color(primary ? t.solid : t.input)
      .bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground).text_size(11.5)
      .cursor_pointer().hover(s => s.opacity(0.85)).on_click(action).child(label);
  }

  profileRow(profile, liveAgent, isManager, order = null, liveTerminal = null, space = null, workflowRole = "", selected = false) {
    const t = theme();
    const lifecycle = profile.loginState === "waiting" ? "awaiting-user" : profile.loginState === "failed" ? "error" : profile.lifecycle;
    const runtimeStatus = liveAgent?.status ?? (liveTerminal || profile.running ? "working" : "blocked");
    const job = [...this.jobs].reverse().find(row => row.assigneeProfile === profile.id && !["completed", "failed"].includes(row.status));
    const jobStatus = job?.status;
    const routedStatus = jobStatus === "needs-review" ? "done"
      : jobStatus === "needs-input" ? "blocked"
      : job && ["queued", "working", "checking"].includes(jobStatus) ? "working" : runtimeStatus;
    const status = lifecycle === "awaiting-user" || lifecycle === "error" || lifecycle === "needs-restart" ? "blocked" : routedStatus;
    const shownStatus = lifecycle === "awaiting-user" ? "Cần bạn đăng nhập" : lifecycle === "error" ? "Lỗi · Có thể khởi động lại"
      : !liveAgent && (lifecycle === "needs-restart" || profile.authenticated) ? "Cần khởi động lại"
      : jobStatus === "needs-review" ? "Đã gửi Leader"
      : jobStatus === "needs-input" ? "Chờ Leader xử lý"
      : !liveAgent && (liveTerminal || profile.running) ? "Đang khởi động" : statusLabel(status);
    const baseLabel = isManager ? "Leader" : (liveAgent?.program?.name ?? profile.agentFamily ?? profile.agent ?? "Agent");
    const accountLabel = profile.email ? `${baseLabel} · ${profile.email}` : baseLabel;
    const label = order == null ? accountLabel : `${order}. ${accountLabel}`;
    const limit5h = profile.usage?.fiveHour;
    const limitWeek = profile.usage?.week;
    const focusAddress = liveAgent?.address ?? liveTerminal?.address;
    const canRestart = !profile.transient && Boolean(space) && !liveAgent && lifecycle !== "awaiting-user" && profile.authenticated;
    return h_flex().id(`profile-${profile.id}`).h(42).px(9).gap(8).items_center().rounded(8).bg(selected ? t.selected : t.chrome)
      .hover(s => s.bg(t.hover)).when(Boolean(focusAddress) || canRestart, el => el.cursor_pointer().on_click((_event, cx) => {
        // An authenticated profile with no live agent is only a stale shell.
        // Clicking the row should revive the selected profile, not open that
        // dead shell (or any older provider terminal).
        if (canRestart) this.restartProfile(profile, isManager, space, liveTerminal, cx);
        else if (focusAddress) showAgentTerminal(focusAddress);
      }))
      .child(div().text_color(t[status] ?? t.idle).child("●"))
      .child(v_flex().flex_1().min_w(0).child(h_flex().items_center().gap(5)
        .child(div().flex_1().truncate().text_size(12.5).text_color(t.foreground).child(label))
        .when(Boolean(workflowRole), row => row.child(div().px(5).py(1).rounded(5).text_size(8.5).text_color(workflowRole === "Leader" ? t.accent : t.muted).bg(t.raised).child(workflowRole))))
        .child(div().truncate().text_size(10.5).text_color(status === "idle" ? "#45c97a" : (t[status] ?? t.dim)).child(shownStatus)))
      .child(v_flex().w(48).items_end().text_size(9.5)
        .child(div().text_color(limitTone(t, limit5h)).child(`5H ${limit5h == null ? "—" : `${limit5h}%`}`))
        .child(div().text_color(limitTone(t, limitWeek)).child(`W  ${limitWeek == null ? "—" : `${limitWeek}%`}`)))
      .when(canRestart, el => el.child(div().id(`restart-${profile.id}`).w(24).h(24).rounded(6).items_center().justify_center().text_color(t.working).cursor_pointer()
        .hover(s => s.bg(t.raised)).on_click((_e, cx) => { cx.stop_propagation(); this.restartProfile(profile, isManager, space, liveTerminal, cx); }).child("↻")))
      .when(!profile.transient, el => el.child(div().id(`delete-${profile.id}`).w(24).h(24).rounded(6).items_center().justify_center().text_color(t.dim).cursor_pointer()
        .hover(s => s.bg(t.raised).text_color(t.blocked)).on_click((_e, cx) => { cx.stop_propagation(); this.askDelete(profile); }).child("×")));
  }

  railProfile(profile, liveAgent, liveTerminal = null, role = "", selected = false) {
    const t = theme();
    const lifecycle = profile.loginState === "waiting" ? "awaiting-user" : profile.loginState === "failed" ? "error" : profile.lifecycle;
    const runtimeStatus = liveAgent?.status ?? (liveTerminal || profile.running ? "working" : "blocked");
    const job = [...this.jobs].reverse().find(row => row.assigneeProfile === profile.id && !["completed", "failed"].includes(row.status));
    const routedStatus = job?.status === "needs-review" ? "done"
      : job?.status === "needs-input" ? "blocked"
      : job && ["queued", "working", "checking"].includes(job.status) ? "working" : runtimeStatus;
    const status = lifecycle === "awaiting-user" || lifecycle === "error" || lifecycle === "needs-restart" ? "blocked" : routedStatus;
    const focusAddress = liveAgent?.address ?? liveTerminal?.address;
    return div().id(`profile-rail-${profile.id}`).w(32).h(32).rounded(9).items_center().justify_center()
      .bg(selected ? t.selected : role === "Leader" ? t.raised : t.chrome).text_color(t[status] ?? t.idle)
      .when(Boolean(focusAddress), el => el.cursor_pointer().hover(s => s.bg(t.hover)).on_click(() => showAgentTerminal(focusAddress)))
      .child("●");
  }

  jobCard(job) {
    const t = theme();
    const needsUser = job.status === "needs-input" || job.status === "awaiting-approval";
    const title = needsUser ? "Cần bạn" : ({ queued: "Đang chờ agent", checking: "Đang kiểm tra", "needs-review": "Chờ Leader tổng hợp", "awaiting-approval": "Chờ bạn xác nhận" }[job.status] ?? "Đang làm");
    const handoff = [job.previousAssignees ?? [], job.assignee ? [job.assignee] : []].flat().filter(Boolean).join(" → ");
    return v_flex().id(`job-${job.id}`).mx(1).px(9).py(7).gap(2).rounded(8).border_1().border_color(needsUser ? t.blocked : t.border).bg(t.surface)
      .when(Boolean(job.assignee), el => el.cursor_pointer().on_click(() => showAgentTerminal(job.assignee)))
      .child(h_flex().items_center().justify_between()
        .child(div().text_size(10.5).font_semibold().text_color(needsUser ? t.blocked : t.working).child(title))
        .child(div().text_size(9.5).text_color(t.dim).child(job.assignee || "Chờ Leader phân công")))
      .child(div().truncate().text_size(11).text_color(t.foreground).child(job.result || job.task))
      .child(this.jobSteps(job))
      .child(div().truncate().text_size(9).text_color(t.dim)
        .child(`${job.contextProfile === "lean" ? "Lean" : "Full"} · ${asArray(job.checkpoints).length} checkpoint · ${asArray(job.evidence).length} bằng chứng · ${asArray(job.artifacts).length} sản phẩm · ${asArray(job.reviewFindings).filter(f => f.status === "open").length} review mở`))
      .when(Boolean(handoff) || Number(job.backupCount ?? 0) > 0, el => el.child(div().truncate().text_size(9.5).text_color(t.dim)
        .child(`Lần ${job.attempt ?? 1} · ${job.backupCount ?? 0} backup${handoff ? ` · ${handoff}` : ""}`)))
      .when(job.status === "awaiting-approval", el => el.child(h_flex().pt(4).gap(5).justify_end()
        .child(this.miniAction(`deny-${job.id}`, "Từ chối", () => this.denyApproval(job)))
        .child(this.miniAction(`approve-${job.id}`, "Xác nhận", () => this.askApproveJob(job), true))));
  }

  miniAction(id, label, action, primary = false) {
    const t = theme();
    return h_flex().id(id).h(24).px(8).items_center().rounded(6).border_1().border_color(primary ? t.solid : t.input)
      .bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground).text_size(9.5)
      .cursor_pointer().hover(s => s.opacity(0.85)).on_click((_e, cx) => { cx.stop_propagation(); action(cx); }).child(label);
  }

  jobSteps(job) {
    const t = theme();
    const stage = job.stage ?? "execution";
    const index = stage === "planning" ? 0 : stage === "execution" ? 1 : stage === "automatic-gate" ? 2 : stage === "review" ? 3 : stage === "approval" ? 4 : stage === "done" ? 5 : 1;
    const labels = ["Leader", "Làm", "Check", "Duyệt", "Bạn"];
    return h_flex().pt(4).items_center().gap(3).children(labels.map((label, i) => {
      const done = index > i || job.status === "completed";
      const active = index === i && job.status !== "completed";
      return h_flex().flex_1().min_w(0).items_center().gap(3)
        .child(div().text_size(8.5).text_color(done ? t.done : active ? t.working : t.dim).child(done ? "●" : active ? "◉" : "○"))
        .child(div().truncate().text_size(8.5).text_color(done || active ? t.foreground : t.dim).child(label));
    }));
  }

  workflowStrip(cfg) {
    const t = theme();
    const steps = ["Bạn", "Leader", "Worker", "Check", "Duyệt"];
    return h_flex().id("workflow-strip").px(8).py(6).gap(3).items_center().rounded(8).border_1().border_color(t.border).bg(t.surface)
      .children(steps.map((step, i) => h_flex().flex_1().min_w(0).items_center().justify_center().gap(3)
        .child(div().truncate().text_size(9).text_color(i === 0 ? t.accent : t.muted).child(step))
        .when(i < steps.length - 1, row => row.child(div().text_size(8).text_color(t.dim).child("›")))));
  }

  askApproveJob(job) {
    this.pendingApproval = job;
    openOverlay({ mod: "confirm", kind: "dialog", width: 450, height: 230, props: {
      title: `Xác nhận cho ${job.id}?`,
      detail: "Xác nhận chỉ cho phép Leader tiếp tục hành động đang chờ. App không tự merge, deploy hoặc xoá dữ liệu.",
      command: { name: "space-manager-hostflow.approve-job" },
    }});
  }

  async approvePendingJob(cx) {
    const job = this.pendingApproval;
    this.pendingApproval = null;
    const space = activeSpace();
    const manager = space ? this.managerTerminal(space) : null;
    if (!job || !space || !manager) return;
    const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
    try {
      await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "update", space.id, job.id, "working", "User approved the pending action."]);
      await hc(["send", manager.address, `Người dùng đã xác nhận hành động đang chờ của jobId=${job.id}. Tiếp tục đúng phạm vi đã duyệt; báo lại kết quả và không mở rộng sang hành động khác.`]);
    } catch (e) { notify({ title: "Chưa xác nhận được", body: String(e.message ?? e), level: "warning" }); }
    this.refresh(cx);
  }

  denyApproval(job) {
    const space = activeSpace();
    const manager = space ? this.managerTerminal(space) : null;
    if (!space || !manager) return;
    (async () => {
      const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
      await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "update", space.id, job.id, "working", "User denied the pending action."]);
      await hc(["send", manager.address, `Người dùng từ chối hành động đang chờ của jobId=${job.id}. Không thực hiện hành động đó; điều chỉnh kế hoạch hoặc tổng hợp để hỏi lại.`]);
    })().catch(e => notify({ title: "Chưa gửi được quyết định", body: String(e.message ?? e), level: "warning" }));
  }

  profileAlert(profile, live, space) {
    const t = theme();
    const failed = profile.loginState === "failed" || profile.lifecycle === "error";
    return v_flex().id(`attention-${profile.id}`).mx(1).px(9).py(7).gap(2).rounded(8).border_1().border_color(t.blocked).bg(t.surface)
      .cursor_pointer().on_click((_event, cx) => {
        if (failed || !live?.terminal?.address) this.restartProfile(profile, false, space, live?.terminal, cx);
        else showAgentTerminal(live.terminal.address);
      })
      .child(div().text_size(10.5).font_semibold().text_color(t.blocked).child("Cần bạn"))
      .child(div().truncate().text_size(11).text_color(t.foreground).child(`${profile.agentFamily || profile.provider || "Agent"}${profile.email ? ` · ${profile.email}` : ""}`))
      .child(div().truncate().text_size(10).text_color(t.dim).child(failed ? "Bấm để đăng nhập lại." : "Bấm để mở màn đăng nhập hoặc xác nhận Trust."));
  }

  render() {
    const t = theme();
    const space = activeSpace();
    if (!space) return v_flex().size_full().p(12).text_color(t.dim).child("Chọn một Space");
    const cfg = this.config(space);
    const host = this.host(space);
    const manager = this.managerAgent(space);
    const managerTerminal = this.managerTerminal(space);
    const signedIn = this.signedInProfile(space, cfg, managerTerminal);
    const activeTabId = space.tabs?.find(tab => tab.active)?.id ?? "";
    const liveAgents = agents().filter(a => a.space === space.id);
    setAgentOrder(liveAgents.map(a => a.address));
    const byProfile = new Map(terminals().filter(t => t.labels?.["herdr.profile"]).map(t => [t.labels["herdr.profile"], {
      terminal: t,
      agent: liveAgents.find(a => a.address === t.address),
    }]));
    const profiles = [...(this.profiles[space.id] ?? [])].sort((a, b) => {
      const aCreated = Date.parse(a.createdAt ?? "") || Number.MAX_SAFE_INTEGER;
      const bCreated = Date.parse(b.createdAt ?? "") || Number.MAX_SAFE_INTEGER;
      return aCreated - bCreated || String(a.id).localeCompare(String(b.id));
    });
    const managerProfile = profiles.find(p => p.id === signedIn?.id) ?? profiles.find(p => p.agent?.startsWith("manager-"));
    const workers = profiles.filter(p => p !== managerProfile);
    const agentFilter = cfg.agentStatusFilter ?? "";
    const filterLabels = { queued: "Queued", running: "Running", review: "Needs review", done: "Done", "waiting-leader": "Chờ Leader", "waiting-user": "Chờ bạn", result: "Đã có kết quả" };
    const matchesAgentFilter = (profile, live) => {
      if (!agentFilter) return true;
      const address = live?.terminal?.address || live?.agent?.address || profile.liveAgent?.address || "";
      const related = this.jobs.filter(job => job.assigneeProfile === profile.id || (address && job.assignee === address));
      const open = related.filter(job => !["completed", "failed"].includes(job.status));
      const runtimeStatus = live?.agent?.status || profile.liveAgent?.status || "idle";
      if (agentFilter === "running") return runtimeStatus === "working" || open.some(job => ["queued", "working", "checking"].includes(job.status));
      if (agentFilter === "queued") return open.some(job => job.status === "queued");
      if (agentFilter === "review") return open.some(job => ["needs-review", "needs-input", "awaiting-approval"].includes(job.status));
      if (agentFilter === "done") return related.some(job => job.status === "completed");
      if (agentFilter === "waiting-leader") return open.some(job => job.status === "needs-review" || job.status === "needs-input");
      if (agentFilter === "waiting-user") return runtimeStatus === "blocked" || profile.loginState === "waiting" || profile.loginState === "failed" || profile.lifecycle === "error" || open.some(job => job.status === "awaiting-approval");
      if (agentFilter === "result") return related.some(job => job.status === "completed" || job.status === "needs-review");
      return true;
    };
    const workerEntries = workers.map((profile, index) => ({ profile, index, live: byProfile.get(profile.id) }));
    const visibleWorkers = workerEntries.filter(entry => matchesAgentFilter(entry.profile, entry.live));
    const profileAlerts = profiles.filter(p => p.loginState === "waiting" || p.loginState === "failed" || p.lifecycle === "error")
      .map(profile => ({ profile, live: byProfile.get(profile.id) }));
    const mapped = new Set([...byProfile.values()].map(entry => entry.agent?.address).filter(Boolean));
    const unmatched = liveAgents.filter(a => a.address !== manager?.address && !mapped.has(a.address)).map(a => {
      const words = (a.tab_name ?? "").toLowerCase().replace(/^\d+\s*/, "").replace(/[^a-z0-9]+/g, " ").split(/\s+/).filter(w => w.length >= 3);
      const family = a.program?.key ?? "";
      const matched = this.allProfiles.find(p => (p.agentFamily || p.agent) === family && p.email && words.some(w => p.email.toLowerCase().replace(/[^a-z0-9]/g, "").includes(w)));
      return { id: `live-${a.address}`, agent: family || "agent", agentFamily: a.program?.name ?? "Agent", email: matched?.email ?? "", usage: matched?.usage, running: true, transient: true, liveAgent: a };
    });
    const unmatchedEntries = unmatched.map((profile, index) => ({ profile, index }));
    const visibleUnmatched = unmatchedEntries.filter(entry => matchesAgentFilter(entry.profile, null));
    const visibleProfileAlerts = !agentFilter || agentFilter === "waiting-user" ? profileAlerts : [];
    if (sidebarNarrow()) {
      return v_flex().id("space-manager-rail").size_full().min_h(0).px(5).py(6).gap(5).items_center().bg(t.chrome)
        .when(Boolean(managerProfile), el => el.child(this.railProfile(managerProfile, manager, managerTerminal, "Leader", manager?.tab === activeTabId || managerTerminal?.tab === activeTabId)))
        .child(div().w(24).h(1).bg(t.border))
        .child(v_flex().flex_1().min_h(0).w_full().items_center().overflow_y_scrollbar().gap(5)
          .children(visibleWorkers.map(({ profile, live }) => {
            return this.railProfile(profile, live?.agent, live?.terminal, "", live?.agent?.tab === activeTabId || live?.terminal?.tab === activeTabId);
          }))
          .children(visibleUnmatched.map(({ profile }) => this.railProfile(profile, profile.liveAgent, null, "", profile.liveAgent?.tab === activeTabId))))
        .child(div().id("add-agent-rail").w(32).h(32).rounded(9).items_center().justify_center().text_size(18).text_color(t.foreground)
          .cursor_pointer().hover(s => s.bg(t.raised)).on_click(() => openOverlay({ mod: "persistent-new-menu", kind: "popup", width: 250, height: 512 })).child("+"));
    }
    const modelParts = String(cfg.model).match(/^(.*)-(low|medium|high|xhigh|max)$/i);
    const modelNames = { "gemini-3.8-flash": "Flash", "gemini-4-argon": "Argon", "claude-opus-5-5": "Opus 5.5", "claude-sonnet-5-5": "Sonnet 5.5", "gpt-oss-120b": "GPT-OSS 120B" };
    const effortLabel = modelParts?.[2] ? modelParts[2][0].toUpperCase() + modelParts[2].slice(1) : "";
    const codexEffort = cfg.effort ? cfg.effort[0].toUpperCase() + cfg.effort.slice(1) : "High";
    const modelLabel = cfg.hostKey === "codex" || cfg.hostKey === "claude"
      ? `${cfg.model === "default" ? "Mặc định" : cfg.model} · ${codexEffort}`
      : cfg.model === "default" ? "Mặc định" : `${modelNames[modelParts?.[1]] ?? modelParts?.[1] ?? cfg.model} · ${effortLabel}`;
    const observedModel = managerTerminal ? this.runtimeModels[managerTerminal.address] : null;
    const requestedRuntimeModel = managerTerminal?.labels?.["herdr.model.requested"];
    const modelMismatch = cfg.model !== "default" && Boolean(observedModel?.id || requestedRuntimeModel)
      && normalizedModel(observedModel?.id || requestedRuntimeModel) !== normalizedModel(cfg.model);
    const approvalLabel = { ask: "Quyền: Cần duyệt", auto: "Quyền: Tự duyệt", full: "Quyền: Toàn quyền" }[cfg.approvalMode] ?? "Quyền: Tự duyệt";
    const runningApprovalMode = managerTerminal?.labels?.["herdr.approval.mode"];
    const approvalMismatch = Boolean(managerTerminal && runningApprovalMode && runningApprovalMode !== cfg.approvalMode);
    const permissionMismatches = terminals().filter(terminal => terminal.labels?.["herdr.space"] === space.id
      && terminal.labels?.["herdr.profile"]
      && terminal.labels?.["herdr.approval.mode"]
      && terminal.labels?.["herdr.approval.mode"] !== cfg.approvalMode);
    return v_flex().id("space-manager").size_full().min_h(0).p(10).gap(8).bg(t.chrome).text_color(t.foreground)
      .child(h_flex().items_center().justify_between().child(div().text_size(11).font_semibold().text_color(t.muted).child("LEADER CỦA SPACE"))
        .child(div().text_size(10.5).text_color(managerTerminal ? t.working : t.dim).child(managerTerminal ? "● Đang bật" : "○ Chưa bật")))
      .child(v_flex().p(9).gap(7).rounded(10).border_1().border_color(t.border).bg(t.surface)
        .child(h_flex().gap(6).items_center().flex_wrap()
          .when(!signedIn, el => el
            .child(this.pill("host-choice", "Chọn Leader", () => this.openHostPicker(space, "accounts")))
            .child(this.pill("host-login", "Đăng nhập", () => this.openHostPicker(space, "login"), true)))
          .when(Boolean(signedIn), el => el
            .child(this.pill("model-choice", modelLabel, () => this.openModelPicker(space)))
            .child(this.pill("workflow-settings", cfg.workflowSetupConfirmed ? "Workflow" : "Thiết lập workflow", () => this.openWorkflowSettings(space)))
            .child(this.pill("approval-settings", approvalLabel, () => this.openPermissionSettings(space)))
            .when(!managerTerminal, row => row.child(this.pill("start-manager", "Bật Leader", () => this.startManager(space), true)))
            .when(modelMismatch && managerTerminal, row => row.child(this.pill("apply-manager-model", "Áp dụng model", () => this.askManagerRestart(space, managerTerminal, observedModel?.label ?? requestedRuntimeModel), true)))
            .when(permissionMismatches.length > 0, row => row.child(this.pill("apply-space-permissions", `Áp dụng quyền (${permissionMismatches.length})`, () => this.askPermissionRestart(space, permissionMismatches), true))))
          .when(modelMismatch, el => el.child(div().text_size(10.5).text_color(t.blocked).child(`Model đang chạy: ${observedModel?.label ?? requestedRuntimeModel} · cần khởi động lại để áp dụng ${modelLabel}`)))
          .when(permissionMismatches.length > 0, el => el.child(div().text_size(10.5).text_color(t.blocked).child(`${permissionMismatches.length} agent đang dùng quyền cũ · cần khởi động lại để áp dụng ${cfg.approvalMode}`))))
        .when(managerProfile, el => el.child(this.profileRow(managerProfile, manager, true, null, managerTerminal, space, "Leader", manager?.tab === activeTabId || managerTerminal?.tab === activeTabId))))
      .child(h_flex().pt(3).items_center().justify_between().child(div().text_size(11).font_semibold().text_color(t.muted).child("AGENT TRONG SPACE"))
        .child(h_flex().items_center().gap(5)
          .when(Boolean(agentFilter), el => el.child(div().id("clear-agent-status-filter").h(25).px(7).rounded(7).items_center().text_size(9.5).text_color(t.accent).bg(t.selected)
            .cursor_pointer().on_click((_event, cx) => { this.save(space, { agentStatusFilter: "" }); cx.notify(); }).child(`${filterLabels[agentFilter] ?? agentFilter} ×`)))
          .child(div().id("add-agent").w(25).h(25).rounded(7).items_center().justify_center().text_size(18).text_color(t.foreground)
            .cursor_pointer().hover(s => s.bg(t.raised)).on_click(() => openOverlay({ mod: "persistent-new-menu", kind: "popup", width: 250, height: 512 })).child("+"))))
      .when(visibleProfileAlerts.length > 0, el => el.child(v_flex().gap(4).children(visibleProfileAlerts.map(({ profile, live }) => this.profileAlert(profile, live, space)))))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().gap(2)
        .children(visibleWorkers.map(({ profile, index, live }) => {
          const role = profile.id === cfg.leadProfileId ? "Leader" : cfg.executorProfileIds.includes(profile.id) ? "Executor" : "";
          return this.profileRow(profile, live?.agent, false, index + 1, live?.terminal, space, role, live?.agent?.tab === activeTabId || live?.terminal?.tab === activeTabId);
        }))
        .children(visibleUnmatched.map(({ profile, index }) => this.profileRow(profile, profile.liveAgent, false, workers.length + index + 1, null, space, "", profile.liveAgent?.tab === activeTabId)))
        .when(visibleWorkers.length + visibleUnmatched.length === 0, el => el.child(div().px(9).py(12).text_size(11.5).text_color(t.dim).child(agentFilter ? `Không có agent ở trạng thái “${filterLabels[agentFilter] ?? agentFilter}”.` : "Chưa có agent. Nhấn + để thêm agent."))));
  }
}
