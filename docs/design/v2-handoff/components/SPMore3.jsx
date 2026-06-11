// SnoozePay — экраны финансов: история, пополнение, способы оплаты.
// Депозит однонаправленный (Google Play Billing / StoreKit IAP) — вывод невозможен.

const { useState: oS3 } = React;

/* 23. TRANSACTION HISTORY
   Period picker — tap "current period" chip → bottom sheet с сеткой
   месяцев по годам. Можно выбрать один месяц или диапазон (тап на
   start и end — все месяцы между ними выделяются).
   Props:
     period     : 'month' (default) | 'range' — какой период отображён
                  в шапке и просуммирован в стат-карточке.
     pickerOpen : boolean — открыт ли bottom sheet выбора периода поверх
                  экрана (для демонстрации UX выбора).
*/
function TxHistory({ period: periodMode = "month", pickerOpen = false } = {}) {
  const [filter, setFilter] = oS3("all");

  /* Single-month vs. range view.
     'month' — текущий месяц, список за один месяц.
     'range' — выбран диапазон 3 мес. (ноя 2025 → янв 2026);
               чип в шапке показывает диапазон, статистика суммируется,
               список транзакций склеен из всех месяцев диапазона
               (группы датируются по убыванию — последний месяц сверху). */
  const isRange = periodMode === "range";

  /* Список транзакций. Для range — 5 групп через все 3 месяца. */
  const txsMonth = [
    { d: "Сегодня",  list: [
      { t: "Поспать ещё · Будни 07:00", a: -50,  ts: "07:05", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:14", i: "snooze" },
    ]},
    { d: "Вчера", list: [
      { t: "Пополнение баланса", a: +500, ts: "21:32", i: "topup" },
      { t: "Бонус: продержались 7 дней", a: +200, ts: "09:00", i: "bonus" },
    ]},
    { d: "12 января", list: [
      { t: "Поспать ещё · Будни 07:00", a: -50,  ts: "07:08", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:17", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -200, ts: "07:26", i: "snooze" },
    ]},
  ];
  const txsRange = [
    { d: "Сегодня",  list: [
      { t: "Поспать ещё · Будни 07:00", a: -50,  ts: "07:05", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:14", i: "snooze" },
    ]},
    { d: "Вчера", list: [
      { t: "Пополнение баланса", a: +500, ts: "21:32", i: "topup" },
    ]},
    { d: "12 января", list: [
      { t: "Поспать ещё · Будни 07:00", a: -50,  ts: "07:08", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:17", i: "snooze" },
    ]},
    { d: "28 декабря", list: [
      { t: "Пополнение баланса", a: +1000, ts: "10:14", i: "topup" },
      { t: "Поспать ещё · Будни 07:00", a: -50,  ts: "07:09", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:18", i: "snooze" },
    ]},
    { d: "14 декабря", list: [
      { t: "Поспать ещё · Выходные 09:00", a: -50,  ts: "09:06", i: "snooze" },
      { t: "Поспать ещё · Выходные 09:00", a: -100, ts: "09:15", i: "snooze" },
    ]},
    { d: "22 ноября", list: [
      { t: "Поспать ещё · Будни 07:00", a: -100, ts: "07:12", i: "snooze" },
      { t: "Поспать ещё · Будни 07:00", a: -200, ts: "07:21", i: "snooze" },
    ]},
  ];
  const txs = isRange ? txsRange : txsMonth;

  /* Суммируем списания, пополнения и считаем число откладываний прямо
     из списка, чтобы статистика всегда сходилась с тем, что видит
     пользователь. Bonus-операции не входят в «Пополнения» — это
     отдельная категория, видимая только в списке. */
  const stats = txs.reduce((acc, g) => {
    g.list.forEach(t => {
      if (t.i === "snooze") { acc.spent += -t.a; acc.snoozes += 1; }
      else if (t.i === "topup") { acc.topups += t.a; }
    });
    return acc;
  }, { spent: 0, topups: 0, snoozes: 0 });

  const period = isRange
    ? { caption: "ноя 2025 — янв 2026", summaryCaption: "ноябрь 2025 — январь 2026" }
    : { caption: "январь 2026",         summaryCaption: "январь 2026" };
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>История</div>
          <div style={{ width: 36 }}/>
        </div>

        {/* Period selector — tappable chip with current period + chevron-down.
            Tap opens the bottom-sheet month picker (см. 21a). */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "center" }}>
          <button
            style={{
              display: "inline-flex", alignItems: "center", gap: 8,
              padding: "10px 12px 10px 16px",
              borderRadius: 999, border: 0,
              background: "var(--sp-white-06)", color: "var(--sp-fg-1)",
              cursor: "pointer",
              font: "600 15px/20px var(--sp-font-body)",
              letterSpacing: "-.01em",
            }}
          >
            <span style={{ textTransform: "capitalize" }}>{period.caption}</span>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M6 9l6 6 6-6"/>
            </svg>
          </button>
        </div>

        {/* Summary card — caption shows the selected period, lowercase.
            Три колонки: списано, пополнения, число откладываний.
            Bonus-операции не агрегируются в шапке — только в списке. */}
        <div style={{ padding: "16px 16px 0" }}>
          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", textTransform: "uppercase" }}>За {period.summaryCaption}</div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 8, gap: 12 }}>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Списано</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-pain-400)" }}>−{fmtRub(stats.spent)}</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Пополнения</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-money-400)" }}>+{fmtRub(stats.topups)}</div>
              </div>
              <div style={{ textAlign: "right" }}>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Откладываний</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>{stats.snoozes}</div>
              </div>
            </div>
          </SPCard>
        </div>

        {/* Tabs */}
        <div style={{ padding: "16px 16px 0", display: "flex", gap: 8 }}>
          {[["all","Все"],["snooze","Списания"],["topup","Поступления"]].map(([id,t])=>(
            <button key={id} onClick={()=>setFilter(id)} style={{
              padding: "8px 12px", borderRadius: 999, border: 0, cursor: "pointer",
              font: "var(--sp-t-button-sm)",
              background: filter===id ? "var(--sp-fg-1)" : "var(--sp-white-06)",
              color: filter===id ? "var(--sp-bg-0)" : "var(--sp-fg-2)",
            }}>{t}</button>
          ))}
        </div>

        {/* Список — высота подбирается под контент, без внутреннего скролла. */}
        <div style={{ padding: "16px 16px 20px", display: "flex", flexDirection: "column", gap: 16 }}>
          {txs.map((g, gi) => (
            <div key={gi}>
              <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>{g.d}</div>
              <SPCard padding="4px 20px" radius={16}>
                {g.list.map((tx, i) => {
                  const neg = tx.a < 0;
                  const colors = {
                    snooze: { bg: "rgba(244,82,63,.14)", fg: "var(--sp-pain-400)" },
                    topup:  { bg: "rgba(43,194,140,.14)", fg: "var(--sp-money-400)" },
                    bonus:  { bg: "rgba(43,194,140,.14)", fg: "var(--sp-money-400)" },
                  }[tx.i];
                  return (
                    <SPRow key={i} divider={i < g.list.length - 1}
                      leading={
                        <div style={{ width: 36, height: 36, borderRadius: 12, background: colors.bg, color: colors.fg,
                          display: "flex", alignItems: "center", justifyContent: "center" }}>
                          {tx.i === "snooze" ? <IconFlame size={18}/> : tx.i === "topup" ? <IconPlus size={18}/> : <IconCheck size={18}/>}
                        </div>
                      }
                      title={tx.t}
                      subtitle={tx.ts}
                      trailing={
                        <span style={{ font: "var(--sp-t-money-md)", color: neg ? "var(--sp-pain-400)" : "var(--sp-money-400)" }}>
                          {neg ? "−" : "+"}{fmtRub(Math.abs(tx.a))}
                        </span>
                      }/>
                  );
                })}
              </SPCard>
            </div>
          ))}
        </div>
      </div>

      {/* Period picker bottom sheet — открыт при pickerOpen=true (фрейм 21b).
          Перекрывает экран снизу скримом + sheet'ом с сеткой месяцев по
          годам, в котором подсвечен выбранный диапазон. */}
      {pickerOpen && <PeriodPickerSheet />}
    </div>
  );
}

/* ───── Period picker bottom sheet ─────
   Сетка месяцев по годам (4×3). Тап на начальный и конечный месяц —
   все месяцы между ними подсвечиваются. Будущие месяцы (после
   текущего — февраль 2026) задизейблены. */
function PeriodPickerSheet() {
  /* Calendar data — годы и месяцы.
     'today' = февраль 2026 (current). После этого месяца — disabled. */
  const ruMonths = ["Янв","Фев","Мар","Апр","Май","Июн","Июл","Авг","Сен","Окт","Ноя","Дек"];
  const years = [2024, 2025, 2026];
  const today = { y: 2026, m: 1 /* Feb, 0-indexed */ };

  /* Selected range: ноя 2025 (y=2025, m=10) → янв 2026 (y=2026, m=0). */
  const start = { y: 2025, m: 10 };
  const end   = { y: 2026, m: 0 };

  /* Linear month index for comparisons. */
  const idx = (p) => p.y * 12 + p.m;
  const sIdx = idx(start), eIdx = idx(end);
  const lo = Math.min(sIdx, eIdx), hi = Math.max(sIdx, eIdx);

  /* Cell role per month: 'start' | 'end' | 'mid' | 'none'. */
  const roleOf = (y, m) => {
    const i = idx({ y, m });
    if (i === sIdx) return "start";
    if (i === eIdx) return "end";
    if (i > lo && i < hi) return "mid";
    return "none";
  };

  const isFuture = (y, m) => idx({ y, m }) > idx(today);

  /* Span helpers — у первой ячейки в строке (m % 4 === 0) range-fill начинается
     слева без extension; у последней (m % 4 === 3) — справа. Иначе extend по
     -4px чтобы перекрыть gap. */
  const rangeBg = "rgba(255,255,255,.10)";

  /* Месяцев между start и end включительно (для подписи кнопки). */
  const rangeLen = hi - lo + 1;

  return (
    <>
      {/* Scrim — translucent чтобы экран под ним был виден. */}
      <div style={{
        position: "absolute", inset: 0,
        background: "rgba(0,0,0,.55)",
        backdropFilter: "blur(2px)",
      }} aria-hidden />

      {/* Sheet */}
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0,
        background: "var(--sp-bg-1)",
        borderTopLeftRadius: 24, borderTopRightRadius: 24,
        boxShadow: "0 -24px 64px rgba(0,0,0,.5)",
        padding: "12px 20px 24px",
        display: "flex", flexDirection: "column", gap: 16,
      }}>
        {/* Drag handle */}
        <div style={{
          width: 36, height: 4, borderRadius: 2,
          background: "var(--sp-white-12)",
          margin: "0 auto",
        }} aria-hidden />

        {/* Header row */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-1)", letterSpacing: "-.01em" }}>
            Период
          </div>
          <button style={{
            border: 0, background: "transparent", padding: "4px 0",
            color: "var(--sp-fg-3)", cursor: "pointer",
            font: "500 14px/20px var(--sp-font-body)",
          }}>Сбросить</button>
        </div>

        {/* Selected range summary — динамическая подпись над сеткой,
            чтобы пользователь видел, что выбрано прямо сейчас. */}
        <div style={{
          display: "flex", alignItems: "center", gap: 10,
          padding: "10px 14px",
          borderRadius: 12,
          background: "var(--sp-white-06)",
        }}>
          <div style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-fg-1)" }} aria-hidden/>
          <div style={{
            font: "600 14px/18px var(--sp-font-body)", color: "var(--sp-fg-1)",
            letterSpacing: "-.01em",
          }}>
            Ноябрь 2025 — Январь 2026
          </div>
          <div style={{ flex: 1 }}/>
          <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>{rangeLen}&nbsp;мес.</div>
        </div>

        {/* Years */}
        <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 2 }}>
          {years.map(y => (
            <div key={y}>
              <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8, padding: "0 4px" }}>
                {y}
              </div>
              {/* Grid 4×3 — gap 0 по горизонтали, чтобы range-fill был непрерывным;
                  вертикальный gap 6. Внутренний padding ячеек создаёт визуальный
                  ритм. */}
              <div style={{
                display: "grid",
                gridTemplateColumns: "repeat(4, 1fr)",
                rowGap: 6,
                columnGap: 0,
              }}>
                {ruMonths.map((mLabel, m) => {
                  const role = roleOf(y, m);
                  const future = isFuture(y, m);
                  const inRange = role !== "none";

                  /* Range fill — full-width strip behind the cell.
                     - start: round left, square right
                     - end: square left, round right
                     - mid: square both sides
                     На границах строки (m % 4 === 0 / 3) — округляем
                     внешний край чтобы фон не вытекал за грид. */
                  const col = m % 4;
                  let fillStyle = null;
                  if (inRange) {
                    let radLeft = 0, radRight = 0;
                    if (role === "start") radLeft = 999;
                    if (role === "end")   radRight = 999;
                    /* Round outer edges of row too, so the range visually
                       wraps cleanly when it spans multiple rows. */
                    if (col === 0) radLeft  = Math.max(radLeft,  14);
                    if (col === 3) radRight = Math.max(radRight, 14);
                    fillStyle = {
                      position: "absolute",
                      top: 4, bottom: 4, left: 0, right: 0,
                      background: rangeBg,
                      borderTopLeftRadius: radLeft,
                      borderBottomLeftRadius: radLeft,
                      borderTopRightRadius: radRight,
                      borderBottomRightRadius: radRight,
                    };
                  }

                  /* Endpoint chip — solid disc on top. */
                  const endpoint = role === "start" || role === "end";

                  return (
                    <div key={m} style={{ position: "relative", height: 44 }}>
                      {fillStyle && <div style={fillStyle} aria-hidden/>}
                      <button
                        disabled={future}
                        style={{
                          position: "relative",
                          width: "100%", height: "100%",
                          border: 0, background: "transparent",
                          padding: 0, margin: 0,
                          cursor: future ? "default" : "pointer",
                          display: "flex", alignItems: "center", justifyContent: "center",
                        }}
                      >
                        <span style={{
                          display: "inline-flex", alignItems: "center", justifyContent: "center",
                          minWidth: 44, height: 36,
                          padding: "0 6px",
                          borderRadius: 999,
                          background: endpoint ? "var(--sp-fg-1)" : "transparent",
                          color: endpoint
                            ? "var(--sp-bg-0)"
                            : future
                              ? "var(--sp-fg-4)"
                              : (role === "mid" ? "var(--sp-fg-1)" : "var(--sp-fg-2)"),
                          font: endpoint
                            ? "700 14px/18px var(--sp-font-body)"
                            : "500 14px/18px var(--sp-font-body)",
                          letterSpacing: "-.01em",
                        }}>{mLabel}</span>
                      </button>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        {/* Apply */}
        <div style={{ marginTop: 6 }}>
          <SPButton variant="money" size="lg" full>Применить</SPButton>
        </div>
      </div>
    </>
  );
}

/* 19. DEPOSIT — bottom-sheet overlay over Wallet (screen 18).
   Picking amount is a modal action on top of the wallet, not a separate
   destination. Underlying wallet is dimmed via scrim, sheet sits at the bottom
   with rounded top, drag handle, the 6 preset cards, CTA, and disclaimer. */
function Deposit() {
  const presetData = [
    { v: 50,   l: <>≈ 1<br/>откладывание</> },
    { v: 250,  l: <>≈ 5<br/>откладываний</>, popular: true },
    { v: 400,  l: <>≈ 8<br/>откладываний</> },
    { v: 500,  l: <>≈ 10<br/>откладываний</> },
    { v: 700,  l: <>≈ 14<br/>откладываний</> },
    { v: 1000, l: <>≈ 20<br/>откладываний</> },
  ];
  const [amount, setAmount] = oS3(250);

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "var(--sp-bg-0)" }}>
      {/* Underlying wallet — inert, peeking through the scrim. */}
      <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }} aria-hidden>
        <WalletV2 />
      </div>
      {/* Scrim — translucent so the wallet below is visibly present. */}
      <div style={{
        position: "absolute", inset: 0,
        background: "rgba(0,0,0,.55)",
        backdropFilter: "blur(2px)",
      }} />

      {/* Sheet */}
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0,
        background: "var(--sp-bg-1)",
        borderTopLeftRadius: 24, borderTopRightRadius: 24,
        boxShadow: "0 -24px 64px rgba(0,0,0,.5)",
        padding: "12px 16px 24px",
        display: "flex", flexDirection: "column", gap: 16,
      }}>
        {/* Drag handle */}
        <div style={{
          width: 36, height: 4, borderRadius: 2,
          background: "var(--sp-white-12)",
          margin: "0 auto",
        }} aria-hidden />

        <div style={{ font: "var(--sp-t-h2)", color: "var(--sp-fg-1)", letterSpacing: "-.01em" }}>
          Пополнить баланс
        </div>

        {/* Preset grid — same set + popular badge on 250 ₽. */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
          {presetData.map(p => (
            <SPAmountPreset
              key={p.v}
              value={p.v}
              label={p.l}
              popular={p.popular}
              selected={amount === p.v}
              onClick={() => setAmount(p.v)}
            />
          ))}
        </div>

        {/* CTA + disclaimer */}
        <div style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: 4 }}>
          <SPButton variant="money" size="lg" full icon={<IconWallet size={20}/>} suffix={fmtRubTight(amount)}>
            Пополнить
          </SPButton>
          <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center" }}>
            Деньги попадают в баланс. Списываются только при откладывании.
          </div>
        </div>
      </div>
    </div>
  );
}

/* Apple Pay logo mark — единая иконка для всех способов оплаты.
   Чёрный плашка-чип с глифом в стиле Apple Pay (упрощённый ⓅPay). */
function ApplePayMark() {
  return (
    <div style={{
      width: 40, height: 28, borderRadius: 6, background: "#000",
      display: "flex", alignItems: "center", justifyContent: "center",
      gap: 2, color: "#FFF",
    }}>
      <svg width="10" height="13" viewBox="0 0 18 22" fill="none" aria-hidden>
        <path d="M14.6 11.7c0-2 1.6-3 1.7-3-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.7-3.1.7-.7 0-1.7-.7-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.3 1 8.4.7 1 1.6 2.1 2.7 2 1.1 0 1.5-.7 2.7-.7 1.3 0 1.6.7 2.7.7 1.1 0 1.9-1 2.5-2 .8-1.1 1.1-2.2 1.2-2.3 0 0-2.3-.9-2.3-3.5zM12.7 5.5c.6-.7 1-1.7.9-2.7-.9 0-1.9.6-2.5 1.3-.5.6-1 1.6-.9 2.6 1 .1 1.9-.5 2.5-1.2z" fill="currentColor"/>
      </svg>
      <span style={{ font: "700 10px/10px var(--sp-font-body)", letterSpacing: "-.02em" }}>Pay</span>
    </div>
  );
}

/* 26. PAYMENT METHODS — V2 (не в MVP).
   Полупрозрачный оверлей сверху с плашкой «V2 · не в MVP» —
   визуальный маркер, что экран запланирован, но сейчас не реализуется. */
function PaymentMethods() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "var(--sp-bg-0)" }}>
      {/* Underlying screen — inert, peeking through the scrim. */}
      <div style={{ position: "absolute", inset: 0, pointerEvents: "none", filter: "saturate(.4)" }} aria-hidden>
        <PaymentMethodsContent />
      </div>
      {/* Scrim */}
      <div style={{
        position: "absolute", inset: 0,
        background: "rgba(6,9,18,.72)",
        backdropFilter: "blur(2px)",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}>
        {/* V2 badge */}
        <div style={{
          display: "flex", flexDirection: "column", alignItems: "center", gap: 12,
          padding: "20px 28px",
          borderRadius: 20,
          background: "rgba(20,26,42,.92)",
          border: "1px solid var(--sp-white-12)",
          boxShadow: "0 24px 64px rgba(0,0,0,.5)",
        }}>
          <div style={{
            padding: "4px 12px",
            borderRadius: 999,
            background: "var(--sp-grad-warn)",
            color: "var(--sp-fg-on-warn)",
            font: "var(--sp-t-caps)",
            letterSpacing: ".12em",
          }}>V2</div>
          <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-1)", letterSpacing: "-.01em" }}>
            Не входит в MVP
          </div>
          <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center", maxWidth: 240 }}>
            Способы оплаты — управление картами и СБП — запланированы на будущую версию.
          </div>
        </div>
      </div>
    </div>);

}

/* Underlying content for screen 22 — kept intact so the V2 overlay sits over
   a real-looking screen. Renamed from the original PaymentMethods body. */
function PaymentMethodsContent() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Способы оплаты</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "20px 16px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Hero: единственный способ оплаты — Apple Pay.
              Чёрная карточка а-ля iOS Wallet, без VISA/МИР визуалов. */}
          <div style={{ position: "relative", borderRadius: 20, padding: 22, height: 200,
            background: "linear-gradient(135deg, #15151A 0%, #0A0A0E 100%)",
            border: "1px solid rgba(255,255,255,.10)" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)" }}>По умолчанию</div>
              <div style={{ display: "flex", alignItems: "center", gap: 4, color: "#FFF" }}>
                <svg width="20" height="24" viewBox="0 0 18 22" fill="none" aria-hidden>
                  <path d="M14.6 11.7c0-2 1.6-3 1.7-3-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.7-3.1.7-.7 0-1.7-.7-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.3 1 8.4.7 1 1.6 2.1 2.7 2 1.1 0 1.5-.7 2.7-.7 1.3 0 1.6.7 2.7.7 1.1 0 1.9-1 2.5-2 .8-1.1 1.1-2.2 1.2-2.3 0 0-2.3-.9-2.3-3.5zM12.7 5.5c.6-.7 1-1.7.9-2.7-.9 0-1.9.6-2.5 1.3-.5.6-1 1.6-.9 2.6 1 .1 1.9-.5 2.5-1.2z" fill="currentColor"/>
                </svg>
                <span style={{ font: "700 18px/22px var(--sp-font-body)", letterSpacing: "-.02em" }}>Pay</span>
              </div>
            </div>
            <div style={{ position: "absolute", left: 22, bottom: 22 }}>
              <div className="sp-caps" style={{ color: "rgba(255,255,255,.4)" }}>Привязанная карта</div>
              <div style={{ font: "20px/24px var(--sp-font-mono)", color: "#FFF", letterSpacing: ".1em", fontVariantNumeric: "tabular-nums", marginTop: 4 }}>
                •••• 4827
              </div>
              <div className="sp-meta" style={{ color: "rgba(255,255,255,.5)", marginTop: 6 }}>
                Управляется в приложении Wallet
              </div>
            </div>
          </div>

          {/* Альтернатива — СБП. Других карт нет: всё через Apple Pay/Wallet. */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Альтернатива</div>
            <SPCard padding="4px 20px" radius={16}>
              <SPRow divider={false} leading={
                <div style={{ width: 40, height: 28, borderRadius: 6, background: "var(--sp-white-08)",
                  display: "flex", alignItems: "center", justifyContent: "center", font: "10px/10px var(--sp-font-mono)", color: "var(--sp-fg-2)" }}>СБП</div>
              } title="Система быстрых платежей" subtitle="+7 ••• ••• 24 18" trailing={<IconChevR size={16}/>}/>
            </SPCard>
          </div>

          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>Безопасность</div>
          <SPCard padding={20} radius={16}>
            <div style={{ display:"flex", gap: 12, alignItems:"flex-start" }}>
              <IconLock size={20} style={{ color: "var(--sp-money-400)", marginTop: 2 }}/>
              <div>
                <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>Только Apple Pay</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-2)", marginTop: 4 }}>
                  Мы не видим номер карты и не храним платёжные данные. Каждое списание подтверждается Face ID и проходит через Apple.
                </div>
              </div>
            </div>
          </SPCard>
        </div>
      </div>
    </div>
  );
}

/* V2Overlay — переиспользуемая обёртка-маркер для экранов, которые
   запланированы но не входят в MVP. Дублирует визуал, использованный на
   экране 22 (PaymentMethods): полупрозрачный scrim + плашка «V2 · Не
   входит в MVP» с поясняющей подписью. Underlying screen остаётся под
   ним десатурированным и инертным. */
function V2Overlay({ children, caption }) {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "var(--sp-bg-0)" }}>
      {/* Underlying screen — inert, peeking through the scrim. */}
      <div style={{ position: "absolute", inset: 0, pointerEvents: "none", filter: "saturate(.4)" }} aria-hidden>
        {children}
      </div>
      {/* Scrim */}
      <div style={{
        position: "absolute", inset: 0,
        background: "rgba(6,9,18,.72)",
        backdropFilter: "blur(2px)",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}>
        {/* V2 badge */}
        <div style={{
          display: "flex", flexDirection: "column", alignItems: "center", gap: 12,
          padding: "20px 28px",
          borderRadius: 20,
          background: "rgba(20,26,42,.92)",
          border: "1px solid var(--sp-white-12)",
          boxShadow: "0 24px 64px rgba(0,0,0,.5)",
        }}>
          <div style={{
            padding: "4px 12px",
            borderRadius: 999,
            background: "var(--sp-grad-warn)",
            color: "var(--sp-fg-on-warn)",
            font: "var(--sp-t-caps)",
            letterSpacing: ".12em",
          }}>V2</div>
          <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-1)", letterSpacing: "-.01em" }}>
            Не входит в MVP
          </div>
          {caption && (
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center", maxWidth: 260 }}>
              {caption}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { TxHistory, PeriodPickerSheet, Deposit, PaymentMethods, PaymentMethodsContent, ApplePayMark, V2Overlay });
