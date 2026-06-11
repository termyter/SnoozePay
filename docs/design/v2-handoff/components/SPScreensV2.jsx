// SnoozePay v2 — улучшенные экраны.
// Цель: атмосфера + ясная иерархия + продуктовый якорь (цена откладывания).
// 3 варианта firing-screen + остальные ключевые.

const { useState: uS, useEffect: uE, useRef: uR } = React;

/* ───── Phone shell ───── */
function Phone({ children, theme = "dark", label, width, height }) {
  /* width/height (optional) — override default 393×852 phone shell.
     Used for setup screens whose natural content height differs from
     the standard viewport, or for iPhone 14 width (390). */
  const phoneStyle = {};
  if (width) phoneStyle.width = width;
  if (height) phoneStyle.height = height;
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
      <div className="phone" style={Object.keys(phoneStyle).length ? phoneStyle : undefined}>
        <div className="phone__notch" />
        <div data-theme={theme} className="phone__screen" style={{ background: "var(--sp-bg-0)" }}>
          {children}
        </div>
        <div className="phone__home" />
      </div>
      {label && <div style={{ font: "var(--sp-t-caps)", color: "var(--sp-fg-3)" }}>{label}</div>}
    </div>);

}

/* ───── Animated price pulse — общий ───── */
function PulseDot({ color = "rgba(255,184,77,.6)" }) {
  return (
    <span style={{
      display: "inline-block", width: 8, height: 8, borderRadius: "50%",
      background: color, boxShadow: `0 0 0 0 ${color}`,
      animation: "sp-pulse 1.6s var(--sp-ease-out) infinite"
    }} />);

}

/* ============================================================
   FIRING — Вариант A: «Dawn» (атмосферный, тёплый)
   ============================================================ */
function FiringDawn({ progressive }) {
  const price = progressive ? 200 : 50;
  const tone = progressive ? "pain" : "warn";
  const next = progressive ? price * 2 : null;

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* атмосферный фон: тёмная ночь + восходящее тепло снизу */}
      <div style={{
        position: "absolute", inset: 0,
        background: "radial-gradient(140% 70% at 50% 100%, rgba(245,158,11,.22) 0%, rgba(244,82,63,.10) 30%, transparent 60%), linear-gradient(180deg, #0A0E1A 0%, #0E1320 60%, #1A1410 100%)"
      }} />
      {/* «солнце» */}
      <div style={{
        position: "absolute", left: "50%", bottom: "-120px", transform: "translateX(-50%)",
        width: 320, height: 320, borderRadius: "50%",
        background: progressive ?
        "radial-gradient(circle, rgba(244,82,63,.35) 0%, rgba(244,82,63,.08) 40%, transparent 70%)" :
        "radial-gradient(circle, rgba(255,184,77,.40) 0%, rgba(245,158,11,.10) 40%, transparent 70%)",
        filter: "blur(20px)"
      }} />

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* верх: дата + баланс */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.55)" }}>Пт · 27 апр</div>
          <SPPill tone={progressive ? "pain" : "money"} icon={<IconCoin size={12} />}>
            {fmtRub(progressive ? 540 : 840)}
          </SPPill>
        </div>

        {/* центр: время */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 16px" }}>
          <div style={{
            font: "var(--sp-t-clock-xl)", color: "#FFF",
            letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums",
            textShadow: "0 4px 60px rgba(255,184,77,.25)"
          }}>
            <span>07</span>
            <span style={{ opacity: .35, padding: "0 4px" }}>:</span>
            <span>00</span>
          </div>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)", marginTop: 8 }}>Подъём</div>
          {progressive &&
          <div style={{ marginTop: 16, display: "flex", alignItems: "center", gap: 8 }}>
              <PulseDot color="rgba(244,82,63,.8)" />
              <span className="sp-caps" style={{ color: "var(--sp-pain-300)", letterSpacing: ".18em" }}>Прогрессив · 4-е откладывание</span>
            </div>
          }
        </div>

        {/* низ: snooze + я встал */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 12 }}>
          <SPSnoozePrice
            price={price}
            tone={tone}
            minutes={5}
            hint={next ? <>Следующее откладывание: {fmtRub(next)}</> : "Цена фиксированная"} />
          
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </div>);

}

/* ============================================================
   FIRING — Вариант B: «Money on the line» (продуктовый, цифра-первая)
   Цена СВЕРХУ как hero, время — поддержка.
   ============================================================ */
function FiringMoneyFirst({ progressive }) {
  const price = progressive ? 200 : 50;
  const next = progressive ? price * 2 : null;
  const tone = progressive ? "pain" : "warn";

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: progressive ? "#1A0A0A" : "#0E1320" }}>
      {/* Тёплое свечение цены сверху */}
      <div style={{
        position: "absolute", top: -80, left: "50%", transform: "translateX(-50%)",
        width: 480, height: 320, borderRadius: "50%",
        background: progressive ?
        "radial-gradient(circle, rgba(244,82,63,.45) 0%, transparent 60%)" :
        "radial-gradient(circle, rgba(255,184,77,.40) 0%, transparent 60%)",
        filter: "blur(40px)"
      }} />

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* hero: цена доминирует */}
        <div style={{ padding: "32px 16px 0", textAlign: "center" }}>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
            <PulseDot color={progressive ? "rgba(244,82,63,.7)" : "rgba(255,184,77,.7)"} />
            <span className="sp-caps" style={{ color: "rgba(255,255,255,.6)", letterSpacing: ".18em" }}>
              Поспать ещё сейчас стоит
            </span>
          </div>
          <div style={{
            font: "700 96px/96px var(--sp-font-mono)",
            background: progressive ? "var(--sp-grad-pain)" : "var(--sp-grad-warn)",
            WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent",
            letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums"
          }}>
            {price}<span style={{ fontSize: 56, opacity: .85 }}>&nbsp;₽</span>
          </div>
          {next &&
          <div className="sp-meta" style={{ color: "rgba(255,255,255,.55)", marginTop: 8 }}>
              следующее откладывание: <span style={{ fontFamily: "var(--sp-font-mono)", color: "rgba(255,255,255,.85)" }}>{fmtRub(next)}</span>
            </div>
          }
        </div>

        {/* time + balance */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "0 16px" }}>
          <div style={{
            font: "200 64px/64px var(--sp-font-mono)", color: "rgba(255,255,255,.85)",
            letterSpacing: "-.03em", fontVariantNumeric: "tabular-nums"
          }}>
            07:00
          </div>
          <div style={{ marginTop: 24, display: "flex", gap: 8 }}>
            <SPPill icon={<IconCoin size={12} />} tone="money">Баланс {fmtRub(progressive ? 540 : 840)}</SPPill>
          </div>
        </div>

        {/* CTA */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 12 }}>
          <button className={`sp-btn sp-btn--lg sp-btn--full sp-btn--${tone === "pain" ? "pain" : "warn"}`}>
            <IconClock size={18} />
            <span className="sp-btn__label">Откупиться · спать ещё 5 мин</span>
          </button>
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </div>);

}

/* ============================================================
   FIRING — Вариант C: «Minimal» (айфон-чистый, без атмосферы)
   ============================================================ */
function FiringMinimal({ progressive }) {
  const price = progressive ? 200 : 50;
  return (
    <div style={{ position: "absolute", inset: 0, background: "#000" }}>
      <SPStatusBar time="7:00" tone="light" />
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 16px" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.45)" }}>Будильник</div>
          <div style={{ font: "100 128px/128px var(--sp-font-mono)", color: "#FFF", marginTop: 12, letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>
            07:00
          </div>
          <div style={{ marginTop: 40, height: 1, width: 60, background: "rgba(255,255,255,.2)" }} />
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.45)", marginTop: 24 }}>Цена откладывания</div>
          <div style={{
            font: "700 56px/60px var(--sp-font-mono)",
            color: progressive ? "var(--sp-pain-400)" : "var(--sp-warn-400)",
            marginTop: 4
          }}>
            {fmtRub(price)}
          </div>
        </div>

        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 8 }}>
          <button style={{
            height: 64, borderRadius: 32, border: 0, cursor: "pointer",
            background: "transparent", color: "rgba(255,255,255,.85)",
            font: "var(--sp-t-button)",
            border: "1.5px solid rgba(255,255,255,.2)"
          }}>
            Отложить · −{fmtRub(price)}
          </button>
          <button style={{
            height: 64, borderRadius: 32, border: 0, cursor: "pointer",
            background: "#FFF", color: "#000",
            font: "var(--sp-t-button)"
          }}>
            Я встал
          </button>
        </div>
      </div>
    </div>);

}

/* ============================================================
   FIRING — No balance (доработанный)
   ============================================================ */
function FiringNoBalanceV2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, #0E1320 0%, #160B0B 100%)", overflow: "hidden" }}>
      <SPStatusBar time="7:00" tone="light" />
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "flex-end" }}>
          <SPPill tone="pain" icon={<IconCoin size={12} />}>Баланс 0 ₽</SPPill>
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 16px", textAlign: "center" }}>
          <div style={{ font: "var(--sp-t-clock-xl)", color: "#FFF", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>07:00</div>
          <div style={{
            marginTop: 28, padding: "10px 12px",
            background: "rgba(244,82,63,.12)", borderRadius: 999,
            border: "1px solid rgba(244,82,63,.3)",
            display: "inline-flex", alignItems: "center", gap: 8
          }}>
            <IconCoinOff size={14} style={{ color: "var(--sp-pain-300)" }} />
            <span className="sp-caps" style={{ color: "var(--sp-pain-300)" }}>Баланса не осталось</span>
          </div>
          <div style={{ marginTop: 18, color: "rgba(255,255,255,.7)", maxWidth: 260, font: "var(--sp-t-body-lg)" }}>
            Откладывать больше не получится. Только встать.
          </div>
        </div>

        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 10 }}>
          {/* Тот же DawnSnoozeButton что и на активном firing-экране — disabled.
               «Спать ещё 5 мин» с IconClock, цена −50 ₽ через тот же глиф (моно, dawn-snooze__cur).
               Меняется только opacity/grayscale — лейаут и типографика заморожены. */}
          <DawnSnoozeButton price={50} tone="warn" minutes={5} disabled hint="Недостаточно средств" />

          {/* Главное действие — пополнить баланс в один тап.
               Tone «money» — зелёный градиент, как на остальных money-CTA. */}
          <SPButton variant="money" size="lg" full icon={<IconWallet size={20} />} suffix={fmtRubTight(500)}>
            Пополнить
          </SPButton>

          {/* Вторичное действие — выключить будильник.
               Тот же .dawn-wake что и на активном firing-экране, с IconCheck слева. */}
          <button
            className="dawn-wake"
            style={{
              background: "transparent",
              color: "rgba(255,255,255,.85)",
              border: "1.5px solid rgba(255,255,255,.18)",
              boxShadow: "none"
            }}>
            
            <IconCheck size={18} />
            Я встал — выключить
          </button>
        </div>
      </div>
    </div>);

}

/* ============================================================
   ALARMS LIST v2 — главный экран
   Props:
     zeroBalance — boolean. Если true, карточка баланса показывает 0 ₽,
                   переключается в pain-тон, кнопка «Пополнить» становится
                   primary CTA. Будильники не отключаются визуально, но
                   рядом появляется явная подсказка, что они не зазвонят
                   без баланса.
   ============================================================ */
function AlarmsListV2({ zeroBalance = false } = {}) {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        {/* === STICKY HEADER: title + balance === */}
        <div style={{
          padding: "16px 16px 16px",
          background: "var(--sp-bg-0)",
          borderBottom: "1px solid var(--sp-white-06)",
          flexShrink: 0,
          position: "relative", zIndex: 2
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Будильники</div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              {/* Settings — opens screen 23 */}
              <button style={{
                width: 40, height: 40, borderRadius: 20, border: 0,
                background: "var(--sp-white-06)", color: "var(--sp-fg-2)",
                display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
              }} aria-label="Настройки">
                <IconSettings size={18} />
              </button>
              <button style={{
                width: 40, height: 40, borderRadius: 20, border: 0,
                background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
                display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
                boxShadow: "var(--sp-shadow-money)"
              }} aria-label="Новый будильник">
                <IconPlus size={20} />
              </button>
            </div>
          </div>

          {/* Balance pill — компактный sticky.
               Сумма + подпись «хватит на N» — в две строки внутри центрального блока,
               чтобы не наезжать на кнопку «Пополнить».
               При zeroBalance — pain-тон, цифра 0 в pain-цвете, подпись
               предупреждает что будильники не сработают; кнопка «Пополнить»
               сохраняет money-variant (это всё-таки положительное действие). */}
          <div role="button" tabIndex={0} style={{
            marginTop: 12, width: "100%", padding: "12px 12px",
            borderRadius: 14,
            border: zeroBalance ? "1px solid rgba(244,82,63,.30)" : "1px solid var(--sp-white-08)",
            background: zeroBalance
              ? "linear-gradient(135deg, rgba(244,82,63,.10) 0%, rgba(244,82,63,.02) 100%)"
              : "var(--sp-bg-2)",
            cursor: "pointer",
            display: "flex", alignItems: "center", gap: 12, textAlign: "left"
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: 10,
              background: zeroBalance ? "var(--sp-grad-pain)" : "var(--sp-grad-money)",
              display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
            }}>
              {zeroBalance
                ? <IconCoinOff size={18} style={{ color: "#FFF" }} />
                : <IconWallet size={18} style={{ color: "var(--sp-fg-on-money)" }} />}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
                <span className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Баланс</span>
                <span style={{
                  font: "700 14px/18px var(--sp-font-mono)",
                  color: zeroBalance ? "var(--sp-pain-300)" : "#FFF",
                  fontVariantNumeric: "tabular-nums",
                  letterSpacing: "0"
                }}>{zeroBalance ? "0 ₽" : fmtRub(840)}</span>
              </div>
              <div className="sp-meta" style={{
                color: zeroBalance ? "var(--sp-pain-300)" : "var(--sp-fg-3)",
                marginTop: 2,
              }}>
                {zeroBalance ? "Откладывать не получится" : "Хватит на ~16 откладываний"}
              </div>
            </div>
            <SPButton variant="money" size="sm">Пополнить</SPButton>
          </div>
        </div>

        {/* === SCROLL AREA === */}
        <div style={{ flex: 1, overflowY: "auto", padding: "16px 16px 20px", display: "flex", flexDirection: "column", gap: 12 }}>
          {/* Streak summary */}
          <div style={{
            padding: "14px 16px", borderRadius: 16,
            background: "linear-gradient(135deg, rgba(46,219,159,.12) 0%, rgba(46,219,159,.04) 100%)",
            border: "1px solid rgba(46,219,159,.18)",
            display: "flex", alignItems: "center", gap: 12
          }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10, background: "var(--sp-grad-money)",
              display: "flex", alignItems: "center", justifyContent: "center"
            }}>
              <IconFlame size={18} style={{ color: "#052016" }} />
            </div>
            <div style={{ flex: 1 }}>
              <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>5 дней без откладываний</div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-2)" }}>Сэкономили 250 ₽</div>
            </div>
            <IconChevR size={16} style={{ color: "var(--sp-fg-3)" }} />
          </div>

          <SPCard tone="raised" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Будни · Пн–Пт</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-1)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  07:00
                </div>
              </div>
              <SPSwitch checked={true} onChange={() => {}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14, flexWrap: "wrap" }}>
              <SPPill tone="warn" icon={<IconRubleCoin size={12} />}>{fmtRub(50)}</SPPill>
              <SPPill tone="pain" icon={<IconTrendUp size={12} />}>×2</SPPill>
              <SPPill icon={<IconSound size={12} />}>Soft Dawn</SPPill>
            </div>
          </SPCard>

          <SPCard tone="surface" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Выходные</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  09:30
                </div>
              </div>
              <SPSwitch checked={false} onChange={() => {}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14 }}>
              <SPPill>{fmtRub(20)}</SPPill>
              <SPPill>Birds</SPPill>
            </div>
          </SPCard>

          <SPCard tone="surface" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Спорт · Вт, Чт</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  06:15
                </div>
              </div>
              <SPSwitch checked={false} onChange={() => {}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14 }}>
              <SPPill tone="warn">{fmtRub(100)}</SPPill>
              <SPPill>Energy</SPPill>
            </div>
          </SPCard>
        </div>

        <SPTabBar active="alarms" />
      </div>
    </div>);

}

/* ============================================================
   WALLET v2 — top-level tab (not a child screen).
   Page-title header (no back arrow) + bottom tab bar with "wallet" active.
   Picking amount lives on screen 19 (Deposit).
   ============================================================ */
function WalletV2() {
  const recentTx = [
    { t: "Поспать ещё · Будни 07:00", a: -50, ts: "Сегодня · 07:09", neg: true },
    { t: "Пополнение баланса",        a: +500, ts: "Вчера · 21:32", neg: false },
    { t: "Бонус: продержались 7 дней", a: +200, ts: "Вчера · 09:00", neg: false },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        {/* Page header — same pattern as Будильники: large h1 + trailing
            primary action. "Пополнить" lives here (top-right pill) instead of
            a bottom CTA, since the bottom is the tab bar. */}
        <div style={{
          padding: "16px 16px 16px",
          background: "var(--sp-bg-0)",
          borderBottom: "1px solid var(--sp-white-06)",
          flexShrink: 0,
          position: "relative", zIndex: 2,
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Кошелёк</div>
            <SPButton variant="money" size="sm" icon={<IconPlus size={16} />}>Пополнить</SPButton>
          </div>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column" }}>
          <div style={{ padding: "16px 16px 0" }}>
            <SPBalanceCard balance={840} delta={-160} hint="Хватит на ~17 откладываний при текущей цене" />
          </div>

          {/* Weekly mini-chart */}
          <div style={{ padding: "24px 16px 0" }}>
            <div className="sp-caps" style={{ marginBottom: 10 }}>Последние 7 дней</div>
            <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 60 }}>
              {[40, 0, 80, 50, 0, 0, 30].map((v, i) =>
                <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                  <div style={{
                    width: "100%", height: v ? `${v}%` : 4,
                    borderRadius: 4, minHeight: 4,
                    background: v ? "var(--sp-grad-pain)" : "var(--sp-white-08)",
                    opacity: v ? 1 : .5
                  }} />
                  <div className="sp-meta" style={{ color: "var(--sp-fg-4)", fontSize: 10 }}>
                    {["П", "В", "С", "Ч", "П", "С", "В"][i]}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Recent transactions preview — last 3 rows, link to full history on screen 21 */}
          <div style={{ padding: "24px 16px 0" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 10 }}>
              <div className="sp-caps">История операций</div>
              <button style={{
                background: "transparent", border: 0, padding: 0, cursor: "pointer",
                color: "var(--sp-money-400)", font: "var(--sp-t-button-sm)",
              }}>Все операции →</button>
            </div>
            <SPCard padding="4px 20px" radius={16}>
              {recentTx.map((tx, i) => (
                <SPRow
                  key={i}
                  divider={i < recentTx.length - 1}
                  leading={
                    <div style={{
                      width: 36, height: 36, borderRadius: 12,
                      background: tx.neg ? "rgba(244,82,63,.14)" : "rgba(43,194,140,.14)",
                      color: tx.neg ? "var(--sp-pain-400)" : "var(--sp-money-400)",
                      display: "flex", alignItems: "center", justifyContent: "center"
                    }}>
                      {tx.neg ? <IconFlame size={18}/> : <IconPlus size={18}/>}
                    </div>
                  }
                  title={tx.t}
                  subtitle={tx.ts}
                  trailing={
                    <span style={{
                      font: "var(--sp-t-money-md)",
                      color: tx.neg ? "var(--sp-pain-400)" : "var(--sp-money-400)",
                    }}>
                      {tx.neg ? "−" : "+"}{fmtRub(Math.abs(tx.a))}
                    </span>
                  }
                />
              ))}
            </SPCard>
          </div>

          {/* Disclaimer — quiet footer line, replaces the old bottom CTA copy. */}
          <div className="sp-meta" style={{ textAlign: "center", color: "var(--sp-fg-4)", padding: "20px 16px 16px" }}>
            Покупка не возвращается · штрафы списываются с баланса
          </div>
        </div>

        <SPTabBar active="wallet" />
      </div>
    </div>);

}

/* ============================================================
   ALARM CARD WRAP DEMO — наглядно показывает, как ведёт себя
   заголовок карточки будильника при разной длине.
   Три карточки одна под другой:
     • короткое имя (умещается),
     • длинное имя на границе одной строки (~26 симв.),
     • очень длинное (переносится на 2 строки).
   Текст никогда не обрезается — карточка просто растёт по высоте.
   Маркер ширины 240 px показан тонкой линией справа от заголовка.
   ============================================================ */
function AlarmCardWrapDemo() {
  const cards = [
    { name: "Будни · Пн–Пт", note: "13 симв · 107 px" },
    { name: "Понедельник тренировка зал", note: "26 симв · 237 px · на пределе одной строки" },
    { name: "Ранний подъём перед работой", note: "27 симв · 243 px · переносится на 2 строки" },
    { name: "Утренняя тренировка перед работой каждый рабочий день недели", note: "61 симв · 3 строки" }];

  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ padding: "16px 16px 0", flexShrink: 0 }}>
        <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Перенос заголовка</div>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 6 }}>
          Доступная ширина под заголовком ≈ 240 px (после padding карточки и места под свитч).
          Текст не обрезается — длинные имена переносятся на следующую строку, карточка растёт.
        </div>
      </div>
      <div style={{ padding: "16px 16px 20px", display: "flex", flexDirection: "column", gap: 12 }}>
        {cards.map((c, idx) =>
          <SPCard key={idx} tone="raised" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 8 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>{c.name}</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-1)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  07:00
                </div>
              </div>
              <SPSwitch checked={true} onChange={() => {}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14, flexWrap: "wrap" }}>
              <SPPill tone="warn" icon={<IconRubleCoin size={12} />}>{fmtRub(50)}</SPPill>
              <SPPill icon={<IconSound size={12} />}>Soft Dawn</SPPill>
            </div>
            <div className="sp-meta" style={{ marginTop: 12, color: "var(--sp-fg-4)", fontFamily: "var(--sp-font-mono)" }}>
              {c.note}
            </div>
          </SPCard>
        )}
      </div>
    </div>);
}

/* ============================================================
   CREATE ALARM v2
   ============================================================ */
function RepeatSegmented({ value, onChange }) {
  /* Two-option pill: Никогда (one-shot) / Еженедельно (weekly).
     Visual rhythm matches the day-of-week chips above — same money
     gradient for the active state, neutral white-06 for the inactive
     side. A short caption below explains the chosen behaviour so the
     user understands what changes without leaving the screen. */
  const opts = [
    { id: "once", label: "Никогда", hint: "Будильник сработает в выбранные дни один раз и отключится." },
    { id: "weekly", label: "Еженедельно", hint: "Будет повторяться каждую неделю по выбранным дням." }];
  const active = opts.find((o) => o.id === value) || opts[1];
  return (
    <div style={{ marginTop: 20 }}>
      <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Повтор</div>
      <div style={{
        display: "inline-flex", padding: 4, borderRadius: 999,
        background: "var(--sp-white-06)", gap: 4
      }}>
        {opts.map((o) => {
          const on = o.id === value;
          return (
            <button
              key={o.id}
              onClick={() => onChange(o.id)}
              style={{
                border: 0, cursor: "pointer",
                padding: "8px 18px", borderRadius: 999,
                background: on ? "var(--sp-grad-money)" : "transparent",
                color: on ? "var(--sp-fg-on-money)" : "var(--sp-fg-2)",
                font: "var(--sp-t-button-sm)",
                transition: "background var(--sp-dur-quick) var(--sp-ease-out), color var(--sp-dur-quick) var(--sp-ease-out)"
              }}>
              {o.label}
            </button>);
        })}
      </div>
      <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 8, maxWidth: 280, marginLeft: "auto", marginRight: "auto" }}>
        {active.hint}
      </div>
    </div>);
}

function CreateAlarmV2() {
  const [name, setName] = uS("");
  const [snoozeMin, setSnoozeMin] = uS(9);
  const [prog, setProg] = uS(true);
  const [price, setPrice] = uS(50);
  const [repeat, setRepeat] = uS("weekly");
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>

        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconClose size={18} />
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Новый будильник</div>
          <SPButton variant="money" size="sm">Готово</SPButton>
        </div>

        {/* Name input — iOS Reminders style */}
        <div style={{ padding: "12px 16px 0" }}>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Название"
            style={{
              width: "100%", border: 0, outline: "none", background: "transparent",
              color: "var(--sp-fg-1)", caretColor: "var(--sp-warn-400)",
              font: "var(--sp-t-h1)", letterSpacing: "-.02em",
              padding: "8px 0 12px",
              borderBottom: "1px solid var(--sp-white-08)"
            }} />
          
        </div>

        {/* Wheel-time picker */}
        <div style={{ padding: "20px 16px 0", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 6 }}>Подъём</div>
          <div style={{ display: "inline-flex", alignItems: "baseline", gap: 4 }}>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>07</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-4)", padding: "0 4px" }}>:</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>00</span>
          </div>
          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 12 }}>
            {["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"].map((d, i) => {
              const on = i < 5;
              return (
                <button key={d} style={{
                  width: 36, height: 36, borderRadius: 18, border: 0,
                  background: on ? "var(--sp-grad-money)" : "var(--sp-white-06)",
                  color: on ? "var(--sp-fg-on-money)" : "var(--sp-fg-3)",
                  font: "var(--sp-t-button-sm)",
                  cursor: "pointer"
                }}>{d}</button>);

            })}
          </div>
          <RepeatSegmented value={repeat} onChange={setRepeat} />
        </div>

        <div style={{ padding: "24px 16px 0", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflowY: "auto" }}>

          {/* Длительность снуза — ползунок 1..15 мин */}
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 12 }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Длительность откладывания</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>На сколько отодвигается звонок</div>
              </div>
              <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>
                {snoozeMin} <span style={{ font: "var(--sp-t-h4)", color: "var(--sp-fg-3)" }}>мин</span>
              </div>
            </div>
            <input
              type="range" min={1} max={15} step={1} value={snoozeMin}
              onChange={(e) => setSnoozeMin(+e.target.value)}
              className="sp-range-warn"
              style={{
                width: "100%",
                height: 6, borderRadius: 3,
                background: `linear-gradient(90deg, var(--sp-warn-500) 0%, var(--sp-warn-500) ${(snoozeMin - 1) / 14 * 100}%, rgba(255,255,255,.10) ${(snoozeMin - 1) / 14 * 100}%, rgba(255,255,255,.10) 100%)`,
                outline: "none", cursor: "pointer"
              }} />
            
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
              <span className="sp-meta" style={{ color: "var(--sp-fg-4)" }}>1 мин</span>
              <span className="sp-meta" style={{ color: "var(--sp-fg-4)" }}>15 мин</span>
            </div>
          </SPCard>

          <SPCard padding="4px 20px" radius={20}>
            <SPRow
              leading={<IconSound size={20} style={{ color: "var(--sp-fg-3)" }} />}
              title="Звук"
              trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16} /></>} />
            
            <SPRow
              leading={<div style={{ width: 28, height: 28, borderRadius: 8, overflow: "hidden",
                background: "linear-gradient(135deg, #2B1A0E 0%, #6B3517 50%, #C46A1A 100%)" }} />}
              title="Тема"
              trailing={<><span className="sp-meta">Рассвет</span><IconChevR size={16} /></>} />
            
            <SPRow
              divider={false}
              leading={<IconBell size={20} style={{ color: "var(--sp-fg-3)" }} />}
              title="Вибрация"
              trailing={<SPSwitch checked={true} onChange={() => {}} />} />
            
          </SPCard>

          {/* Snooze price — editable amount with quick-fill chips. */}
          <SnoozePriceCard value={price} onChange={setPrice} />

          <SPCard padding={20} radius={20}
          style={prog ? { background: "linear-gradient(135deg, rgba(244,82,63,.10), rgba(244,82,63,.02))", border: "1px solid rgba(244,82,63,.25)" } : {}}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
              <div style={{ flex: 1 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <IconFlame size={18} style={{ color: prog ? "var(--sp-pain-400)" : "var(--sp-fg-3)" }} />
                  <div className="sp-h4">Прогрессивный режим</div>
                </div>
                <div className="sp-meta" style={{ marginTop: 6, color: "var(--sp-fg-3)" }}>
                  Каждое откладывание — в 2 раза дороже.
                </div>
                {prog &&
                <div style={{ marginTop: 12, display: "flex", gap: 8, alignItems: "center", fontFamily: "var(--sp-font-mono)" }}>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 14 }}>50</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 14 }}>100</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 14 }}>200</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 16, fontWeight: 700 }}>{fmtRub(400)}</span>
                  </div>
                }
              </div>
              <SPSwitch checked={prog} onChange={setProg} />
            </div>
          </SPCard>
        </div>

      </div>
    </div>);

}

/* ============================================================
   STREAK MODAL v2 — поведенческая победа.
   Без денежных сумм (это про привычку, не про экономию) и без
   "Поделиться победой" (фича V2). Остаётся иконка серии, надпись
   "7 дней без откладываний", дорожка дней 1—7 и кнопка "Закрыть".
   Мотивационный текст подчёркивает, что серия — это привычка, а не
   случайность.
   ============================================================ */
function StreakModalV2() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* dimmed underlying screen hint */}
      <div style={{
        position: "absolute", inset: 0,
        background: "linear-gradient(180deg, rgba(6,9,18,.92) 0%, rgba(6,9,18,.85) 100%)"
      }} />
      {/* glow */}
      <div style={{
        position: "absolute", left: "50%", bottom: 100, transform: "translateX(-50%)",
        width: 400, height: 400, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.30) 0%, transparent 60%)",
        filter: "blur(40px)"
      }} />

      <SPStatusBar time="7:01" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: "0 12px 16px" }}>
        <div style={{
          background: "var(--sp-bg-2)", borderRadius: 28, padding: 28,
          textAlign: "center", position: "relative", overflow: "hidden",
          border: "1px solid rgba(46,219,159,.20)",
          boxShadow: "0 -20px 60px -10px rgba(46,219,159,.20)"
        }}>
          {/* corner glow */}
          <div style={{
            position: "absolute", top: -60, right: -60,
            width: 200, height: 200, borderRadius: "50%",
            background: "radial-gradient(circle, rgba(46,219,159,.18) 0%, transparent 70%)"
          }} />

          <div style={{
            width: 96, height: 96, borderRadius: 28,
            background: "var(--sp-grad-money)", margin: "0 auto",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "0 12px 40px rgba(46,219,159,.40)", position: "relative"
          }}>
            <IconFlame size={48} style={{ color: "#052016" }} />
          </div>

          <div className="sp-caps" style={{ marginTop: 20, color: "var(--sp-money-300)" }}>Серия</div>

          {/* Hero — поведенческая победа, без денег. */}
          <div style={{
            font: "var(--sp-t-h1)", marginTop: 6,
            color: "var(--sp-fg-1)",
            letterSpacing: "-.02em",
          }}>
            7 дней без откладываний
          </div>

          <div className="sp-body" style={{ marginTop: 10, color: "var(--sp-fg-2)", maxWidth: 300, margin: "10px auto 0" }}>
            Это уже не случайность — это привычка.<br/>
            Тело знает, что подъём во время — это просто.
          </div>

          {/* Days streak — 1 → 7 */}
          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 24 }}>
            {[1, 2, 3, 4, 5, 6, 7].map((d) =>
            <div key={d} style={{
              width: 32, height: 32, borderRadius: 10,
              background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
              display: "flex", alignItems: "center", justifyContent: "center",
              font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)"
            }}>
                {d}
              </div>
            )}
          </div>

          <div style={{ marginTop: 24 }}>
            <SPButton variant="money" size="lg" full>Закрыть</SPButton>
          </div>
        </div>
      </div>
    </div>);

}

/* expose */
Object.assign(window, {
  Phone, PulseDot,
  FiringDawn, FiringMoneyFirst, FiringMinimal, FiringNoBalanceV2,
  AlarmsListV2, WalletV2, CreateAlarmV2, StreakModalV2,
  RepeatSegmented, AlarmCardWrapDemo
});