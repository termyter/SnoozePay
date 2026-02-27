// SnoozePay Screen Generator v3 — iOS 26 Native Alarm Style
// Creates alarm firing screens + states + design system

async function main() {
  await figma.loadFontAsync({ family: "Inter", style: "Regular" });
  await figma.loadFontAsync({ family: "Inter", style: "Medium" });
  await figma.loadFontAsync({ family: "Inter", style: "Semi Bold" });
  await figma.loadFontAsync({ family: "Inter", style: "Bold" });
  await figma.loadFontAsync({ family: "Inter", style: "Light" });

  const page = figma.currentPage;
  const W = 393;
  const H = 852;

  // Remove old generated frames
  const genNames = [
    "alarm_firing_screen", "alarm_firing_screen_no_balance",
    "alarm_firing_screen_progressive",
    "empty_alarm_list_state", "streak_congratulation_modal",
    "design_system", "Rectangle 1"
  ];
  for (const child of [...page.children]) {
    if (genNames.includes(child.name)) child.remove();
  }

  // Place after existing content
  let maxX = 0;
  for (const node of page.children) {
    if (node.x + node.width > maxX) maxX = node.x + node.width;
  }
  let X = maxX + 200;

  // ============================================================
  // DESIGN-005: Alarm Firing — iOS 26 Style (Normal)
  // ============================================================
  buildiOS26AlarmScreen("alarm_firing_screen", X, 0, {
    snoozeLabel: "Отложить (50 ₽)",
    snoozeEnabled: true,
    snoozeTint: rgb(255, 149, 0),  // orange accent for price
  });

  // ============================================================
  // DESIGN-005b: Balance = 0
  // ============================================================
  buildiOS26AlarmScreen("alarm_firing_screen_no_balance", X + W + 60, 0, {
    snoozeLabel: "Баланс пуст",
    snoozeEnabled: false,
    snoozeTint: null,
  });

  // ============================================================
  // DESIGN-005c: Progressive (2nd snooze, expensive)
  // ============================================================
  buildiOS26AlarmScreen("alarm_firing_screen_progressive", X + (W + 60) * 2, 0, {
    snoozeLabel: "Отложить (200 ₽)",
    snoozeEnabled: true,
    snoozeTint: rgb(255, 69, 58),  // red = expensive
  });

  // ============================================================
  // DESIGN-009a: Empty Alarm List
  // ============================================================
  buildEmptyAlarmList(X, H + 100);

  // ============================================================
  // DESIGN-009b: Streak Modal
  // ============================================================
  buildStreakModal(X + W + 60, H + 100);

  // ============================================================
  // DESIGN-010: Design System
  // ============================================================
  buildDesignSystem(X, (H + 100) * 2);

  figma.viewport.scrollAndZoomIntoView(page.children);
  figma.notify("✅ SnoozePay v3: iOS 26 alarm style + states + design system");
  figma.closePlugin();
}

// ============================================================
// iOS 26 Alarm Firing Screen
// ============================================================
function buildiOS26AlarmScreen(name, x, y, opts) {
  const W = 393;
  const H = 852;
  const screen = figma.createFrame();
  screen.name = name;
  screen.resize(W, H);
  screen.x = x;
  screen.y = y;
  screen.clipsContent = true;

  // --- Background: dark gradient simulating blurred wallpaper ---
  screen.fills = [{
    type: "GRADIENT_LINEAR",
    gradientStops: [
      { position: 0, color: { r: 0.08, g: 0.06, b: 0.14, a: 1 } },   // deep purple-black
      { position: 0.4, color: { r: 0.05, g: 0.04, b: 0.10, a: 1 } },
      { position: 0.7, color: { r: 0.04, g: 0.06, b: 0.12, a: 1 } },  // dark blue-black
      { position: 1, color: { r: 0.02, g: 0.02, b: 0.06, a: 1 } },
    ],
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  }];

  // --- Subtle ambient light blobs (simulating out-of-focus wallpaper) ---
  const blob1 = figma.createEllipse();
  blob1.name = "ambient_light_1";
  blob1.resize(300, 300);
  blob1.x = -60;
  blob1.y = 50;
  blob1.fills = [{ type: "SOLID", color: rgb(80, 40, 120), opacity: 0.15 }];
  screen.appendChild(blob1);

  const blob2 = figma.createEllipse();
  blob2.name = "ambient_light_2";
  blob2.resize(250, 250);
  blob2.x = 200;
  blob2.y = 500;
  blob2.fills = [{ type: "SOLID", color: rgb(20, 60, 120), opacity: 0.12 }];
  screen.appendChild(blob2);

  // --- Status bar area (simplified) ---
  const statusTime = createText("status_time", "7:30", 15, "Semi Bold", rgba(255,255,255,0.6));
  statusTime.x = 32;
  statusTime.y = 16;
  screen.appendChild(statusTime);

  // --- "БУДИЛЬНИК" label above time ---
  const alarmTypeLabel = createText("alarm_type_label", "БУДИЛЬНИК", 14, "Medium", rgba(255,255,255,0.5));
  alarmTypeLabel.textAlignHorizontal = "CENTER";
  alarmTypeLabel.resize(W, 20);
  alarmTypeLabel.x = 0;
  alarmTypeLabel.y = 220;
  alarmTypeLabel.letterSpacing = { value: 3, unit: "PIXELS" };
  screen.appendChild(alarmTypeLabel);

  // --- Time display (very large, light weight like iOS) ---
  const timeDisplay = createText("time_display", "7:30", 96, "Light", rgb(255, 255, 255));
  timeDisplay.textAlignHorizontal = "CENTER";
  timeDisplay.resize(W, 110);
  timeDisplay.x = 0;
  timeDisplay.y = 260;
  timeDisplay.letterSpacing = { value: -3, unit: "PIXELS" };
  screen.appendChild(timeDisplay);

  // --- Alarm name ---
  const alarmName = createText("alarm_name", "Работа", 22, "Regular", rgba(255,255,255,0.7));
  alarmName.textAlignHorizontal = "CENTER";
  alarmName.resize(W, 30);
  alarmName.x = 0;
  alarmName.y = 382;
  screen.appendChild(alarmName);

  // --- Two side-by-side buttons at bottom (iOS 26 style) ---
  const btnAreaY = H - 160;
  const btnGap = 12;
  const btnW = (W - 32 - btnGap) / 2;  // 16px padding each side
  const btnH = 64;
  const btnRadius = 20;  // iOS 26 uses large capsule-like radius

  // "Выключить" button (left) — frosted glass with GREEN tint
  const stopBtn = figma.createFrame();
  stopBtn.name = "stop_button";
  stopBtn.resize(btnW, btnH);
  stopBtn.x = 16;
  stopBtn.y = btnAreaY;
  stopBtn.cornerRadius = btnRadius;
  stopBtn.fills = [{ type: "SOLID", color: rgb(48, 209, 88), opacity: 0.22 }];
  stopBtn.strokes = [{ type: "SOLID", color: rgb(48, 209, 88), opacity: 0.35 }];
  stopBtn.strokeWeight = 0.5;
  stopBtn.layoutMode = "VERTICAL";
  stopBtn.primaryAxisAlignItems = "CENTER";
  stopBtn.counterAxisAlignItems = "CENTER";
  stopBtn.itemSpacing = 2;

  const stopIcon = createText("stop_icon", "✕", 18, "Medium", rgb(255, 255, 255));
  stopIcon.textAlignHorizontal = "CENTER";
  stopBtn.appendChild(stopIcon);

  const stopLabel = createText("stop_label", "Выключить", 14, "Medium", rgb(255, 255, 255));
  stopLabel.textAlignHorizontal = "CENTER";
  stopBtn.appendChild(stopLabel);

  screen.appendChild(stopBtn);

  // "Отложить" button (right) — frosted glass with tint
  const snoozeBtn = figma.createFrame();
  snoozeBtn.name = "snooze_button";
  snoozeBtn.resize(btnW, btnH);
  snoozeBtn.x = 16 + btnW + btnGap;
  snoozeBtn.y = btnAreaY;
  snoozeBtn.cornerRadius = btnRadius;

  if (opts.snoozeEnabled) {
    // Active: tinted glass
    snoozeBtn.fills = [{ type: "SOLID", color: opts.snoozeTint || rgb(255,149,0), opacity: 0.25 }];
    snoozeBtn.strokes = [{ type: "SOLID", color: opts.snoozeTint || rgb(255,149,0), opacity: 0.4 }];
    snoozeBtn.strokeWeight = 0.5;
  } else {
    // Disabled: dim glass
    snoozeBtn.fills = [{ type: "SOLID", color: rgb(255, 255, 255), opacity: 0.06 }];
    snoozeBtn.strokes = [{ type: "SOLID", color: rgb(255, 255, 255), opacity: 0.08 }];
    snoozeBtn.strokeWeight = 0.5;
  }

  snoozeBtn.layoutMode = "VERTICAL";
  snoozeBtn.primaryAxisAlignItems = "CENTER";
  snoozeBtn.counterAxisAlignItems = "CENTER";
  snoozeBtn.itemSpacing = 2;

  // Use text bell symbol instead of emoji (emoji can't be recolored)
  const snzIcon = createText("snooze_icon", "⏰", 16, "Regular",
    opts.snoozeEnabled ? rgb(255,255,255) : rgb(142,142,147));
  snzIcon.textAlignHorizontal = "CENTER";
  snoozeBtn.appendChild(snzIcon);

  const snzLabel = createText("snooze_label", opts.snoozeLabel, 14, "Medium",
    opts.snoozeEnabled ? rgb(255,255,255) : rgb(142,142,147));
  snzLabel.textAlignHorizontal = "CENTER";
  snoozeBtn.appendChild(snzLabel);

  screen.appendChild(snoozeBtn);

  // --- Home indicator ---
  const homeInd = figma.createRectangle();
  homeInd.name = "home_indicator";
  homeInd.resize(134, 5);
  homeInd.x = (W - 134) / 2;
  homeInd.y = H - 20;
  homeInd.cornerRadius = 3;
  homeInd.fills = [{ type: "SOLID", color: rgb(255,255,255), opacity: 0.3 }];
  screen.appendChild(homeInd);

  return screen;
}

// ============================================================
// Empty Alarm List
// ============================================================
function buildEmptyAlarmList(x, y) {
  const W = 393;
  const H = 852;
  const frame = figma.createFrame();
  frame.name = "empty_alarm_list_state";
  frame.resize(W, H);
  frame.x = x;
  frame.y = y;
  frame.fills = [{ type: "SOLID", color: rgb(0, 0, 0) }];

  // Header
  const title = createText("header_title", "Будильники", 34, "Bold", rgb(255,255,255));
  title.x = 20;
  title.y = 64;
  frame.appendChild(title);

  // Add button
  const addBtn = figma.createFrame();
  addBtn.name = "add_button";
  addBtn.resize(30, 30);
  addBtn.x = W - 50;
  addBtn.y = 68;
  addBtn.cornerRadius = 15;
  addBtn.fills = [{ type: "SOLID", color: rgb(10, 132, 255) }];
  addBtn.layoutMode = "HORIZONTAL";
  addBtn.primaryAxisAlignItems = "CENTER";
  addBtn.counterAxisAlignItems = "CENTER";
  const plus = createText("plus", "+", 20, "Light", rgb(255,255,255));
  addBtn.appendChild(plus);
  frame.appendChild(addBtn);

  // Balance bar
  const balBar = figma.createFrame();
  balBar.name = "balance_bar";
  balBar.resize(W - 32, 60);
  balBar.x = 16;
  balBar.y = 120;
  balBar.cornerRadius = 14;
  balBar.fills = [{ type: "SOLID", color: rgb(10, 132, 255) }];
  balBar.layoutMode = "HORIZONTAL";
  balBar.primaryAxisAlignItems = "SPACE_BETWEEN";
  balBar.counterAxisAlignItems = "CENTER";
  balBar.paddingLeft = 20;
  balBar.paddingRight = 16;

  const balGroup = figma.createFrame();
  balGroup.name = "balance_info";
  balGroup.layoutMode = "VERTICAL";
  balGroup.itemSpacing = 2;
  balGroup.fills = [];
  balGroup.layoutSizingHorizontal = "HUG";
  balGroup.layoutSizingVertical = "HUG";
  const balLabel = createText("bal_label", "БАЛАНС", 11, "Medium", rgba(255,255,255,0.7));
  balGroup.appendChild(balLabel);
  const balAmount = createText("bal_amount", "₽ 0", 24, "Bold", rgb(255,255,255));
  balGroup.appendChild(balAmount);
  balBar.appendChild(balGroup);

  const topUpBtn = figma.createFrame();
  topUpBtn.name = "topup_button";
  topUpBtn.resize(120, 36);
  topUpBtn.cornerRadius = 18;
  topUpBtn.fills = [{ type: "SOLID", color: rgb(255,255,255) }];
  topUpBtn.layoutMode = "HORIZONTAL";
  topUpBtn.primaryAxisAlignItems = "CENTER";
  topUpBtn.counterAxisAlignItems = "CENTER";
  const topUpText = createText("topup_text", "Пополнить", 14, "Semi Bold", rgb(10,132,255));
  topUpBtn.appendChild(topUpText);
  balBar.appendChild(topUpBtn);

  frame.appendChild(balBar);

  // Empty state content
  const emptyIcon = createText("empty_icon", "⏰", 64, "Regular", rgb(255,255,255));
  emptyIcon.textAlignHorizontal = "CENTER";
  emptyIcon.resize(W, 80);
  emptyIcon.x = 0;
  emptyIcon.y = 340;
  frame.appendChild(emptyIcon);

  const emptyTitle = createText("empty_title", "Нет будильников", 22, "Semi Bold", rgb(255,255,255));
  emptyTitle.textAlignHorizontal = "CENTER";
  emptyTitle.resize(W, 30);
  emptyTitle.x = 0;
  emptyTitle.y = 420;
  frame.appendChild(emptyTitle);

  const emptySub = createText("empty_sub", "Нажмите + чтобы создать первый", 16, "Regular", rgb(142,142,147));
  emptySub.textAlignHorizontal = "CENTER";
  emptySub.resize(W, 24);
  emptySub.x = 0;
  emptySub.y = 456;
  frame.appendChild(emptySub);

  // Tab bar
  appendTabBar(frame, 0);
}

// ============================================================
// Streak Congratulation Modal
// ============================================================
function buildStreakModal(x, y) {
  const W = 393;
  const H = 852;
  const outer = figma.createFrame();
  outer.name = "streak_congratulation_modal";
  outer.resize(W, H);
  outer.x = x;
  outer.y = y;
  outer.fills = [{ type: "SOLID", color: rgb(0,0,0), opacity: 0.65 }];

  // Modal card
  const card = figma.createFrame();
  card.name = "modal_card";
  card.resize(340, 340);
  card.x = (W - 340) / 2;
  card.y = (H - 340) / 2;
  card.cornerRadius = 28;
  card.fills = [{ type: "SOLID", color: rgb(44, 44, 46) }];
  card.layoutMode = "VERTICAL";
  card.primaryAxisAlignItems = "CENTER";
  card.counterAxisAlignItems = "CENTER";
  card.paddingTop = 36;
  card.paddingBottom = 28;
  card.paddingLeft = 28;
  card.paddingRight = 28;
  card.itemSpacing = 8;
  outer.appendChild(card);

  // Fire emoji
  const fire = createText("fire", "🔥", 52, "Regular", rgb(255,255,255));
  fire.textAlignHorizontal = "CENTER";
  card.appendChild(fire);

  addSpacer(card, 8);

  // Big number
  const num = createText("streak_num", "12", 64, "Bold", rgb(255, 149, 0));
  num.textAlignHorizontal = "CENTER";
  card.appendChild(num);

  // Label
  const label = createText("streak_label", "дней без откладываний!", 20, "Medium", rgb(255,255,255));
  label.textAlignHorizontal = "CENTER";
  card.appendChild(label);

  addSpacer(card, 4);

  // Saving
  const saving = createText("saving", "Ваша экономия: 600 ₽", 16, "Regular", rgb(48, 209, 88));
  saving.textAlignHorizontal = "CENTER";
  card.appendChild(saving);

  addSpacer(card, 12);

  // OK button
  const okBtn = createGlassButton("ok_button", "Отлично!", 260, 52, rgb(10,132,255), 14);
  card.appendChild(okBtn);
}

// ============================================================
// Design System
// ============================================================
function buildDesignSystem(x, y) {
  const ds = figma.createFrame();
  ds.name = "design_system";
  ds.resize(900, 1300);
  ds.x = x;
  ds.y = y;
  ds.fills = [{ type: "SOLID", color: rgb(0, 0, 0) }];

  // Title
  const t = createText("ds_title", "SnoozePay — Дизайн-система", 34, "Bold", rgb(255,255,255));
  t.x = 40; t.y = 40;
  ds.appendChild(t);

  // COLORS
  const cs = createText("c_sec", "ЦВЕТА", 13, "Semi Bold", rgb(142,142,147));
  cs.x = 40; cs.y = 100;
  ds.appendChild(cs);

  const palette = [
    { n: "Background",   h: "#000000",  c: rgb(0,0,0) },
    { n: "Surface",      h: "#1C1C1E",  c: rgb(28,28,30) },
    { n: "Surface 2",    h: "#2C2C2E",  c: rgb(44,44,46) },
    { n: "Surface 3",    h: "#3A3A3C",  c: rgb(58,58,60) },
    { n: "Glass",        h: "rgba W18%", c: rgb(200,200,200) },
    { n: "Blue",         h: "#0A84FF",  c: rgb(10,132,255) },
    { n: "Green",        h: "#30D158",  c: rgb(48,209,88) },
    { n: "Orange",       h: "#FF9500",  c: rgb(255,149,0) },
    { n: "Red",          h: "#FF453A",  c: rgb(255,69,58) },
    { n: "Text Primary", h: "#FFFFFF",  c: rgb(255,255,255) },
  ];

  palette.forEach((p, i) => {
    const col = i % 5;
    const row = Math.floor(i / 5);
    const sw = figma.createRectangle();
    sw.name = `color_${i}`;
    sw.resize(72, 72);
    sw.x = 40 + col * 100;
    sw.y = 130 + row * 115;
    sw.cornerRadius = 14;
    sw.fills = [{ type: "SOLID", color: p.c, opacity: p.n === "Glass" ? 0.18 : 1 }];
    if (["Background", "Surface"].includes(p.n)) {
      sw.strokes = [{ type: "SOLID", color: rgb(58,58,60) }];
      sw.strokeWeight = 1;
    }
    ds.appendChild(sw);

    const lb = createText(`cl_${i}`, `${p.n}\n${p.h}`, 11, "Regular", rgb(142,142,147));
    lb.x = 40 + col * 100;
    lb.y = 207 + row * 115;
    ds.appendChild(lb);
  });

  // TYPOGRAPHY
  const ts = createText("t_sec", "ТИПОГРАФИКА", 13, "Semi Bold", rgb(142,142,147));
  ts.x = 40; ts.y = 385;
  ds.appendChild(ts);

  const styles = [
    { l: "Large Title — 34 Bold",   t: "Будильники",    s: 34, w: "Bold" },
    { l: "Title 1 — 28 Bold",       t: "Настройки",     s: 28, w: "Bold" },
    { l: "Title 2 — 22 SemiBold",   t: "12 дней без откладываний!",  s: 22, w: "Semi Bold" },
    { l: "Time — 96 Light",         t: "7:30",           s: 64, w: "Light" },
    { l: "Headline — 17 SemiBold",  t: "Работа • Будни", s: 17, w: "Semi Bold" },
    { l: "Body — 17 Regular",       t: "Каждое откладывание x2 дороже", s: 17, w: "Regular" },
    { l: "Footnote — 13 SemiBold",  t: "⚠ ОТЛОЖИТЬ: 50 ₽", s: 13, w: "Semi Bold" },
    { l: "Caption — 12 Regular",    t: "7 февраля в 14:30", s: 12, w: "Regular" },
  ];

  let tY = 415;
  styles.forEach(s => {
    const lb = createText("tl", s.l, 11, "Regular", rgb(142,142,147));
    lb.x = 40; lb.y = tY;
    ds.appendChild(lb);
    const tx = createText("ts", s.t, s.s, s.w, rgb(255,255,255));
    tx.x = 40; tx.y = tY + 16;
    if (s.s >= 64) tx.letterSpacing = { value: -2, unit: "PIXELS" };
    ds.appendChild(tx);
    tY += s.s + 28;
  });

  // SPACING
  const sp = createText("sp_sec", "ОТСТУПЫ", 13, "Semi Bold", rgb(142,142,147));
  sp.x = 560; sp.y = 100;
  ds.appendChild(sp);

  [4,8,12,16,24,32].forEach((v,i) => {
    const bar = figma.createRectangle();
    bar.resize(v * 4, 24);
    bar.x = 560; bar.y = 130 + i * 40;
    bar.cornerRadius = 4;
    bar.fills = [{ type: "SOLID", color: rgb(10,132,255) }];
    ds.appendChild(bar);
    const lb = createText("sp", `${v}px`, 12, "Regular", rgb(142,142,147));
    lb.x = 560 + v * 4 + 12; lb.y = 132 + i * 40;
    ds.appendChild(lb);
  });

  // RADIUS
  const br = createText("br_sec", "BORDER RADIUS", 13, "Semi Bold", rgb(142,142,147));
  br.x = 560; br.y = 385;
  ds.appendChild(br);

  [8,14,20,28].forEach((v,i) => {
    const r = figma.createRectangle();
    r.resize(56, 56);
    r.x = 560 + i * 76; r.y = 415;
    r.cornerRadius = v;
    r.fills = [{ type: "SOLID", color: rgb(44,44,46) }];
    r.strokes = [{ type: "SOLID", color: rgb(58,58,60) }]; r.strokeWeight = 1;
    ds.appendChild(r);
    const lb = createText("br", `${v}px`, 12, "Regular", rgb(142,142,147));
    lb.x = 560 + i * 76 + 16; lb.y = 478;
    ds.appendChild(lb);
  });

  // BUTTONS — iOS 26 Glass Style
  const bs = createText("b_sec", "КНОПКИ (iOS 26 Glass)", 13, "Semi Bold", rgb(142,142,147));
  bs.x = 560; bs.y = 530;
  ds.appendChild(bs);

  const btns = [
    { l: "Stop (Glass Green)", t: "Выключить",       tint: rgb(48,209,88), op: 0.22 },
    { l: "Snooze (Orange)",    t: "Отложить (50 ₽)", tint: rgb(255,149,0),   op: 0.25 },
    { l: "Snooze (Red)",       t: "Отложить (200 ₽)",tint: rgb(255,69,58),   op: 0.25 },
    { l: "Disabled",           t: "Баланс пуст",     tint: rgb(255,255,255), op: 0.06 },
    { l: "Action (Blue)",      t: "Отлично!",        tint: rgb(10,132,255),  op: 0.90 },
  ];

  btns.forEach((b, i) => {
    const lb = createText("bl", b.l, 11, "Regular", rgb(142,142,147));
    lb.x = 560; lb.y = 560 + i * 72;
    ds.appendChild(lb);

    const btn = figma.createFrame();
    btn.name = `btn_${i}`;
    btn.resize(280, 52);
    btn.x = 560; btn.y = 576 + i * 72;
    btn.cornerRadius = 20;
    btn.fills = [{ type: "SOLID", color: b.tint, opacity: b.op }];
    if (b.op < 0.5) {
      btn.strokes = [{ type: "SOLID", color: b.tint, opacity: Math.min(b.op + 0.15, 0.4) }];
      btn.strokeWeight = 0.5;
    }
    btn.layoutMode = "HORIZONTAL";
    btn.primaryAxisAlignItems = "CENTER";
    btn.counterAxisAlignItems = "CENTER";

    const isDisabled = b.l === "Disabled";
    const tx = createText("bt", b.t, 16, "Medium",
      isDisabled ? rgba(255,255,255,0.3) : rgb(255,255,255));
    tx.textAlignHorizontal = "CENTER";
    tx.layoutGrow = 1;
    btn.appendChild(tx);
    ds.appendChild(btn);
  });

  // TOGGLES
  const tgSec = createText("tg_sec", "TOGGLE", 13, "Semi Bold", rgb(142,142,147));
  tgSec.x = 560; tgSec.y = 940;
  ds.appendChild(tgSec);

  // Toggle ON
  const toggleOn = figma.createFrame();
  toggleOn.name = "toggle_on";
  toggleOn.resize(51, 31);
  toggleOn.x = 560; toggleOn.y = 968;
  toggleOn.cornerRadius = 16;
  toggleOn.fills = [{ type: "SOLID", color: rgb(48, 209, 88) }];
  const knobOn = figma.createEllipse();
  knobOn.resize(27, 27);
  knobOn.x = 22; knobOn.y = 2;
  knobOn.fills = [{ type: "SOLID", color: rgb(255,255,255) }];
  toggleOn.appendChild(knobOn);
  ds.appendChild(toggleOn);

  const tgOnLbl = createText("tg_on_lbl", "ON", 12, "Medium", rgb(48, 209, 88));
  tgOnLbl.x = 620; tgOnLbl.y = 974;
  ds.appendChild(tgOnLbl);

  // Toggle OFF
  const toggleOff = figma.createFrame();
  toggleOff.name = "toggle_off";
  toggleOff.resize(51, 31);
  toggleOff.x = 670; toggleOff.y = 968;
  toggleOff.cornerRadius = 16;
  toggleOff.fills = [{ type: "SOLID", color: rgb(142, 142, 147), opacity: 0.4 }];
  const knobOff = figma.createEllipse();
  knobOff.resize(27, 27);
  knobOff.x = 2; knobOff.y = 2;
  knobOff.fills = [{ type: "SOLID", color: rgb(255,255,255) }];
  toggleOff.appendChild(knobOff);
  ds.appendChild(toggleOff);

  const tgOffLbl = createText("tg_off_lbl", "OFF", 12, "Medium", rgb(142, 142, 147));
  tgOffLbl.x = 730; tgOffLbl.y = 974;
  ds.appendChild(tgOffLbl);

  // SETTINGS ROW
  const srSec = createText("sr_sec", "SETTINGS ROW", 13, "Semi Bold", rgb(142,142,147));
  srSec.x = 560; srSec.y = 1020;
  ds.appendChild(srSec);

  // Settings row with chevron
  const settRow = figma.createFrame();
  settRow.name = "settings_row_example";
  settRow.resize(320, 48);
  settRow.x = 560; settRow.y = 1048;
  settRow.cornerRadius = 12;
  settRow.fills = [{ type: "SOLID", color: rgb(44, 44, 46) }];
  settRow.layoutMode = "HORIZONTAL";
  settRow.primaryAxisAlignItems = "SPACE_BETWEEN";
  settRow.counterAxisAlignItems = "CENTER";
  settRow.paddingLeft = 16;
  settRow.paddingRight = 16;

  const srLabel = createText("sr_label", "История транзакций", 17, "Regular", rgb(255,255,255));
  settRow.appendChild(srLabel);
  const srChev = createText("sr_chevron", "›", 22, "Regular", rgb(142,142,147));
  settRow.appendChild(srChev);
  ds.appendChild(settRow);

  // Settings row with toggle
  const settRow2 = figma.createFrame();
  settRow2.name = "settings_row_toggle";
  settRow2.resize(320, 48);
  settRow2.x = 560; settRow2.y = 1108;
  settRow2.cornerRadius = 12;
  settRow2.fills = [{ type: "SOLID", color: rgb(44, 44, 46) }];
  settRow2.layoutMode = "HORIZONTAL";
  settRow2.primaryAxisAlignItems = "SPACE_BETWEEN";
  settRow2.counterAxisAlignItems = "CENTER";
  settRow2.paddingLeft = 16;
  settRow2.paddingRight = 12;

  const sr2Label = createText("sr2_label", "Вибрация", 17, "Regular", rgb(255,255,255));
  settRow2.appendChild(sr2Label);

  const miniToggle = figma.createFrame();
  miniToggle.name = "mini_toggle";
  miniToggle.resize(51, 31);
  miniToggle.cornerRadius = 16;
  miniToggle.fills = [{ type: "SOLID", color: rgb(48, 209, 88) }];
  const miniKnob = figma.createEllipse();
  miniKnob.resize(27, 27);
  miniKnob.x = 22; miniKnob.y = 2;
  miniKnob.fills = [{ type: "SOLID", color: rgb(255,255,255) }];
  miniToggle.appendChild(miniKnob);
  settRow2.appendChild(miniToggle);
  ds.appendChild(settRow2);
}

// ============================================================
// Tab Bar
// ============================================================
function appendTabBar(parent, activeIdx) {
  const W = 393;
  const sep = figma.createRectangle();
  sep.name = "tab_separator";
  sep.resize(W, 0.5);
  sep.x = 0; sep.y = 852 - 83;
  sep.fills = [{ type: "SOLID", color: rgb(58,58,60) }];
  parent.appendChild(sep);

  const bar = figma.createFrame();
  bar.name = "tab_bar";
  bar.resize(W, 83);
  bar.x = 0; bar.y = 852 - 83;
  bar.fills = [{ type: "SOLID", color: rgb(28, 28, 30) }];
  bar.layoutMode = "HORIZONTAL";
  bar.primaryAxisAlignItems = "SPACE_BETWEEN";
  bar.counterAxisAlignItems = "CENTER";
  bar.paddingLeft = 40; bar.paddingRight = 40;
  bar.paddingTop = 8; bar.paddingBottom = 28;

  // Monochrome SF Symbols style tab bar icons (drawn as simple shapes)
  const tabItems = [
    { label: "Будильники" },
    { label: "Статистика" },
    { label: "Настройки" },
  ];

  tabItems.forEach((t, i) => {
    const tab = figma.createFrame();
    tab.name = `tab_${i}`;
    tab.layoutMode = "VERTICAL";
    tab.counterAxisAlignItems = "CENTER";
    tab.itemSpacing = 4;
    tab.fills = [];
    tab.layoutSizingHorizontal = "HUG";
    tab.layoutSizingVertical = "HUG";

    const tintColor = i === activeIdx ? rgb(10,132,255) : rgb(142,142,147);

    // Icon placeholder as a simple geometric shape
    const iconFrame = figma.createFrame();
    iconFrame.name = `tab_icon_${i}`;
    iconFrame.resize(24, 24);
    iconFrame.fills = [];

    if (i === 0) {
      // Alarm: circle with two lines on top (bell shape)
      const bell = figma.createEllipse();
      bell.resize(18, 18);
      bell.x = 3; bell.y = 4;
      bell.fills = [];
      bell.strokes = [{ type: "SOLID", color: tintColor }];
      bell.strokeWeight = 2;
      iconFrame.appendChild(bell);
      const clapper = figma.createRectangle();
      clapper.resize(6, 2);
      clapper.x = 9; clapper.y = 22;
      clapper.cornerRadius = 1;
      clapper.fills = [{ type: "SOLID", color: tintColor }];
      iconFrame.appendChild(clapper);
    } else if (i === 1) {
      // Stats: 3 vertical bars
      [{ x: 2, h: 12 }, { x: 9, h: 18 }, { x: 16, h: 8 }].forEach(b => {
        const bar2 = figma.createRectangle();
        bar2.resize(5, b.h);
        bar2.x = b.x; bar2.y = 24 - b.h;
        bar2.cornerRadius = 2;
        bar2.fills = [{ type: "SOLID", color: tintColor }];
        iconFrame.appendChild(bar2);
      });
    } else {
      // Settings: gear (circle with dot)
      const gear = figma.createEllipse();
      gear.resize(20, 20);
      gear.x = 2; gear.y = 2;
      gear.fills = [];
      gear.strokes = [{ type: "SOLID", color: tintColor }];
      gear.strokeWeight = 2;
      iconFrame.appendChild(gear);
      const dot = figma.createEllipse();
      dot.resize(6, 6);
      dot.x = 9; dot.y = 9;
      dot.fills = [{ type: "SOLID", color: tintColor }];
      iconFrame.appendChild(dot);
    }

    tab.appendChild(iconFrame);

    const lb = createText("lb", t.label, 10, "Medium", tintColor);
    lb.textAlignHorizontal = "CENTER";
    tab.appendChild(lb);

    bar.appendChild(tab);
  });
  parent.appendChild(bar);
}

// ============================================================
// Helpers
// ============================================================
function rgb(r, g, b) {
  return { r: r / 255, g: g / 255, b: b / 255 };
}

function rgba(r, g, b, a) {
  // For text fills we use opacity on the fill itself
  return { r: r / 255, g: g / 255, b: b / 255 };
}

function createText(name, content, size, style, color) {
  const t = figma.createText();
  t.name = name;
  t.fontName = { family: "Inter", style: style };
  t.characters = content;
  t.fontSize = size;
  // Handle opacity through fill opacity
  const opacity = (color === rgba) ? 1 : 1;
  t.fills = [{ type: "SOLID", color: color }];
  return t;
}

function createGlassButton(name, label, w, h, tint, radius) {
  const btn = figma.createFrame();
  btn.name = name;
  btn.resize(w, h);
  btn.cornerRadius = radius;
  btn.fills = [{ type: "SOLID", color: tint, opacity: 0.9 }];
  btn.layoutMode = "HORIZONTAL";
  btn.primaryAxisAlignItems = "CENTER";
  btn.counterAxisAlignItems = "CENTER";

  const tx = createText(`${name}_label`, label, 17, "Semi Bold", rgb(255,255,255));
  tx.textAlignHorizontal = "CENTER";
  tx.layoutGrow = 1;
  btn.appendChild(tx);
  return btn;
}

function addSpacer(parent, h) {
  const s = figma.createFrame();
  s.name = "spacer";
  s.resize(10, h);
  s.fills = [];
  parent.appendChild(s);
}

main();
