import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, TextView } from "gpui-base";
import { spaces, terminals, agents, theme, exec, appHome, hc, notify, shared, setShared } from "herdr";

const CONFIG = "space-manager.config.v1";
const INTENT_MODE = "leader-chat.intent-mode.v1";

function parseJson(stdout, fallback = []) {
  const clean = String(stdout ?? "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim();
  return clean ? JSON.parse(clean) : fallback;
}

function activeSpace() { return spaces().find(space => space.active); }

function messageContent(summary) {
  const attachments = [];
  const text = String(summary ?? "").replace(/\[image:([^\]]+)\]/g, (_match, path) => {
    attachments.push(path);
    return "";
  }).trim();
  return { text, attachments };
}

async function sendTerminalMessage(terminal, message, cx) {
  // Terminal-backed agents all receive text through the same delivery path.
  // Confirm the prompt after inserting it instead of branching by provider;
  // some TUIs report `started` before the submitted text actually begins.
  const result = await hc(["send", terminal.address, message]);
  // `hc send` includes Enter, but paste-heavy TUIs can consume it before the
  // newly pasted prompt settles. A delayed confirmation is harmless on an
  // already submitted prompt and removes that race for every provider.
  await cx.sleep(300);
  await hc(["keys", terminal.address, "enter"]);
  return result;
}

export default class LeaderChat extends View {
  init(_props, cx) {
    this.messages = [];
    this.loading = false;
    this.sending = false;
    this.text = "";
    this.attachments = [];
    this.intent = "chat";
    this.input = InputState.new({ value: "", placeholder: "Nhắn Leader… · Ctrl+V để dán ảnh" });
    this.input.on("change", (_event, innerCx) => { this.text = this.input.value(); innerCx.notify(); });
    this.input.on("submit", (_event, innerCx) => this.queueSubmit(innerCx));
    this.input.on("paste_other", (_event, innerCx) => this.pasteImage(innerCx));
    this.refresh(cx);
    cx.timer.every(2000, innerCx => this.refresh(innerCx));
  }

  pasteImage(cx) {
    const space = activeSpace();
    if (!space) return;
    if (this.attachments.length >= 3) {
      notify({ title: "Tối đa 3 ảnh", body: "Gửi tin nhắn hiện tại trước khi dán thêm ảnh.", level: "warning" });
      return;
    }
    cx.spawn(async innerCx => {
      try {
        const helper = `${appHome()}/mods/leader-chat/save-clipboard-image.ps1`;
        const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", helper, space.id]);
        if (result.code !== 0) throw new Error(result.stderr || "Clipboard không có ảnh.");
        const saved = parseJson(result.stdout, {});
        if (!saved.path) throw new Error("Không đọc được ảnh từ clipboard.");
        this.attachments = [...this.attachments, saved.path];
      } catch (error) {
        notify({ title: "Không dán được ảnh", body: String(error.message ?? error), level: "warning" });
      }
      innerCx.notify();
    });
  }

  removeAttachment(path, cx) {
    this.attachments = this.attachments.filter(item => item !== path);
    cx.notify();
  }

  intentFor(space) {
    if (!space) return "chat";
    return (shared(INTENT_MODE) ?? {})[space.id] ?? "chat";
  }

  setIntent(space, intent, cx) {
    const all = shared(INTENT_MODE) ?? {};
    setShared(INTENT_MODE, { ...all, [space.id]: intent });
    this.intent = intent;
    cx.notify();
  }

  queueSubmit(cx) {
    if (this.sending) return;
    cx.spawn(async innerCx => this.submit(innerCx));
  }

  leaderTerminal(space) {
    if (!space) return null;
    const profileId = shared(CONFIG)?.[space.id]?.profileId;
    const inSpace = terminals().filter(row => row.labels?.["herdr.space"] === space.id);
    if (profileId) return inSpace.find(row => row.labels?.["herdr.profile"] === profileId) ?? null;
    return inSpace.find(row => row.labels?.["herdr.role"] === "manager") ?? null;
  }

  refresh(cx) {
    const space = activeSpace();
    if (!space || this.loading) return;
    this.loading = true;
    cx.spawn(async innerCx => {
      try {
        const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
        const result = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "mailbox", space.id]);
        this.messages = parseJson(result.stdout).slice(-120);
      } catch {}
      this.loading = false;
      innerCx.notify();
    });
  }

  async submit(cx) {
    const space = activeSpace();
    const message = this.text.trim();
    const attachments = [...this.attachments];
    if (!space || (!message && !attachments.length) || this.sending) return;
    const leader = this.leaderTerminal(space);
    if (!leader) {
      notify({ title: "Leader chưa bật", body: "Hãy bật Leader của Space trước khi nhắn.", level: "warning" });
      return;
    }
    const helper = `${appHome()}/mods/space-manager-hostflow/space-jobs.ps1`;
    const payload = [message, ...attachments.map(path => `[image:${path}]`)].filter(Boolean).join("\n");
    const delegate = this.intentFor(space) === "task";
    const recentContext = this.messages
      .filter(row => row.type === "user.message" || row.type === "leader.message")
      .slice(-6)
      .map(row => `${row.type === "user.message" ? "Người dùng" : "Leader"}: ${row.summary || ""}`)
      .join("\n");
    const workerTask = [
      "Thực hiện yêu cầu mới nhất của người dùng trong đúng phạm vi Space hiện tại.",
      recentContext ? `Ngữ cảnh hội thoại gần nhất:\n${recentContext}` : "",
      `Yêu cầu hiện tại:\n${payload}`,
      "Làm trong worktree/nhánh riêng, không sửa main; tự chạy kiểm tra cục bộ và gửi checkpoint, evidence, commit cùng kết quả về Leader để review. Không hỏi người dùng trực tiếp.",
    ].filter(Boolean).join("\n\n");
    const optimistic = {
      id: `pending-${Date.now()}`,
      type: "user.message",
      from: "Bạn",
      to: "Leader",
      summary: payload,
      createdAt: new Date().toISOString(),
      pending: true,
    };
    this.sending = true;
    this.text = "";
    this.attachments = [];
    this.input.set_value("");
    this.messages = [...this.messages, optimistic];
    cx.notify();
    try {
      await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "message", space.id, "user.message", "Bạn", "Leader", payload]);
      if (delegate) {
        const dispatched = await exec("powershell.exe", ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "auto-dispatch", space.id, workerTask]);
        if (dispatched.code !== 0) throw new Error(dispatched.stderr || dispatched.stdout || "Không còn executor rảnh.");
        const job = parseJson(dispatched.stdout, {});
        notify({
          title: job.assignee ? "Đã giao agent" : "Đã xếp hàng",
          body: job.assignee
            ? `Herdr đã giao ${job.id}; Leader sẽ review kết quả.`
            : `Herdr đã lưu ${job.id}; scheduler sẽ tự giao khi có worker phù hợp rảnh.`,
          level: "info",
        });
      } else {
        await sendTerminalMessage(leader, `${payload}\n\nCác marker [image:đường-dẫn] là ảnh người dùng gửi; hãy đọc ảnh trực tiếp từ đường dẫn đó. Chỉ trao đổi, phân tích hoặc trả lời ngắn gọn. Nếu cần sửa code hay thực thi, không tự làm: dùng route-dispatch giao worker. CHAT UI: Nếu câu trả lời chấp nhận kết quả worker, hãy dùng complete-message với khóa ổn định và đúng jobId để vừa ghi câu trả lời vừa đóng task. Chỉ dùng lệnh powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "${helper}" message ${space.id} leader.message Leader Bạn <nội dung trả lời> khi cuộc trao đổi không đóng job nào. Không ghi log, policy hay suy luận nội bộ.`, cx);
      }
      this.refresh(cx);
    } catch (error) {
      this.messages = this.messages.filter(row => row.id !== optimistic.id);
      if (!this.text) {
        this.text = message;
        this.input.set_value(message);
      }
      if (!this.attachments.length) this.attachments = attachments;
      notify({ title: "Không gửi được", body: String(error.message ?? error), level: "warning" });
    } finally {
      this.sending = false;
    }
    cx.notify();
  }

  timeLabel(value) {
    if (!value) return "";
    try { return new Date(value).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }); }
    catch { return ""; }
  }

  messageRow(message) {
    const t = theme();
    const content = messageContent(message.summary);
    const user = message.type === "user.message";
    const leader = message.type === "leader.message";
    if (!user && !leader) {
      const labels = { "task.assigned": "Leader đã giao việc", "result.submitted": "Worker đã trả kết quả", "worker.blocked": "Worker cần hỗ trợ", "result.accepted": "Leader đã tổng hợp", "history.imported": "Bàn giao trước đó" };
      return h_flex().w_full().justify_center().py(5)
        .child(v_flex().max_w(310).px(9).py(6).gap(2).rounded(8).bg(t.raised).border_1().border_color(message.type === "worker.blocked" ? t.blocked : t.border)
          .child(h_flex().items_center().justify_between().gap(8)
            .child(div().truncate().text_size(9.5).font_medium().text_color(message.type === "worker.blocked" ? t.blocked : t.muted).child(labels[message.type] || "Cập nhật nội bộ"))
            .child(div().text_size(8.5).text_color(t.dim).child(this.timeLabel(message.createdAt))))
          .child(TextView.markdown(`internal-${message.id || message.createdAt}`, content.text || "").selectable(true).max_h(38).overflow_hidden().text_size(9).text_color(t.dim)));
    }
    return h_flex().w_full().py(5).when(user, row => row.justify_end()).when(leader, row => row.justify_start())
      .child(v_flex().max_w(315).px(11).py(8).gap(4).rounded(11)
        .bg(user ? t.selected : t.surface).border_1().border_color(user ? t.accent : t.border)
        .child(div().text_size(9).font_medium().text_color(user ? t.accent : t.done).child(user ? "Bạn" : "Leader"))
        .when(Boolean(content.text), bubble => bubble.child(TextView.markdown(`chat-${message.id || message.createdAt}`, content.text).selectable(true).text_size(11).text_color(t.foreground)))
        .when(Boolean(content.attachments.length), bubble => bubble.child(h_flex().gap(6).flex_wrap().children(content.attachments.map(path =>
          image(path).w(132).h(96).rounded(7).border_1().border_color(t.border)
        ))))
        .child(div().text_size(8.5).text_color(t.dim).child(this.timeLabel(message.createdAt))));
  }

  render() {
    const t = theme();
    const space = activeSpace();
    const terminal = this.leaderTerminal(space);
    const live = terminal ? agents().find(row => row.address === terminal.address) : null;
    const working = live?.status === "working";
    const ready = Boolean(terminal) && live?.status !== "blocked";
    const directMessages = this.messages.filter(message => message.type === "user.message" || message.type === "leader.message");
    const waitingForLeader = working && directMessages.at(-1)?.type === "user.message";
    const latestInternal = [...this.messages].reverse().find(message => message.type !== "user.message" && message.type !== "leader.message");
    const intent = this.intentFor(space);
    return v_flex().id("leader-chat").size_full().min_h(0).bg(t.background).text_color(t.foreground)
      .child(h_flex().h(40).px(11).items_center().justify_between().border_b(1).border_color(t.border)
        .child(div().text_size(11.5).font_semibold().child("Chat với Leader"))
        .child(h_flex().items_center().gap(5)
          .child(div().size(6).rounded(4).bg(working ? t.working : ready ? t.done : t.blocked))
          .child(div().text_size(9).text_color(working ? t.working : ready ? t.done : t.dim).child(working ? "Đang xử lý" : ready ? "Sẵn sàng" : "Chưa bật"))))
      .when(Boolean(latestInternal), root => root.child(h_flex().h(26).px(11).items_center().gap(6).border_b(1).border_color(t.border).bg(t.raised)
        .child(div().size(5).rounded(3).bg(latestInternal.type === "worker.blocked" ? t.blocked : t.accent))
        .child(div().flex_1().truncate().text_size(8.8).text_color(t.muted).child(`Cập nhật nội bộ: ${latestInternal.summary || "Có thay đổi mới"}`))))
      .child(v_flex().flex_1().min_h(0).px(10).py(7).overflow_y_scrollbar()
        .children(directMessages.map(message => this.messageRow(message)))
        .when(waitingForLeader, el => el.child(h_flex().w_full().py(5).justify_start()
          .child(h_flex().px(11).py(8).gap(6).items_center().rounded(11).bg(t.surface).border_1().border_color(t.working)
            .child(div().size(6).rounded(4).bg(t.working))
            .child(div().text_size(10.5).text_color(t.muted).child("Leader đang xử lý…")))))
        .when(!directMessages.length, el => el.child(v_flex().flex_1().items_center().justify_center().gap(5)
          .child(div().text_size(12).font_medium().text_color(t.muted).child("Bắt đầu với Leader"))
          .child(div().max_w(260).text_size(10).text_color(t.dim).child("Gửi mục tiêu của bạn. Leader sẽ giao việc cho các agent và trả kết quả tại đây.")))))
      .child(v_flex().p(8).gap(6).border_t(1).border_color(t.border).bg(t.chrome)
        .when(Boolean(space), composer => composer.child(h_flex().gap(5).items_center()
          .child(div().id("leader-intent-chat").h(25).px(8).rounded(7).items_center().text_size(9.5)
            .bg(intent === "chat" ? t.selected : t.raised).text_color(intent === "chat" ? t.accent : t.muted).border_1().border_color(intent === "chat" ? t.accent : t.border)
            .cursor_pointer().on_click((_event, innerCx) => this.setIntent(space, "chat", innerCx)).child("Trao đổi"))
          .child(div().id("leader-intent-task").h(25).px(8).rounded(7).items_center().text_size(9.5)
            .bg(intent === "task" ? t.selected : t.raised).text_color(intent === "task" ? t.working : t.muted).border_1().border_color(intent === "task" ? t.working : t.border)
            .cursor_pointer().on_click((_event, innerCx) => this.setIntent(space, "task", innerCx)).child("Giao việc"))
          .child(div().flex_1().truncate().text_size(8.8).text_color(t.dim).child(intent === "task" ? "Herdr tạo job và giao worker" : "Leader trả lời trực tiếp"))))
        .when(Boolean(this.attachments.length), composer => composer.child(h_flex().gap(7).flex_wrap().children(this.attachments.map((path, index) =>
          v_flex().id(`pasted-image-${index}`).relative().w(82).h(62).rounded(7).overflow_hidden().border_1().border_color(t.border)
            .child(image(path).size_full())
            .child(div().absolute().top(3).right(3).size(18).rounded(9).items_center().justify_center().bg(t.chrome).text_color(t.foreground).text_size(10)
              .cursor_pointer().on_click((_event, innerCx) => this.removeAttachment(path, innerCx)).child("×"))
        ))))
        .child(h_flex().gap(6).items_center()
          .child(Input.new(this.input).flex_1().h(38).px(10).rounded(9).border_1().border_color(t.input).bg(t.surface).text_size(11.5).text_color(t.foreground))
          .child(div().id("leader-chat-send").size(38).rounded(9).items_center().justify_center().bg(t.solid).text_color(t.solid_foreground).text_size(16)
            .cursor_pointer().hover(style => style.opacity(0.85)).on_click((_event, innerCx) => this.queueSubmit(innerCx)).child("➤"))));
  }
}
