// SnoozePay · Firing Theme — состояние ПОСЛЕ нажатия «Отложить».
//
// Снимок экрана через несколько секунд после первого откладывания:
//   • баланс уменьшился (была 50 ₽ списана),
//   • вместо большого "07:00" — countdown "04:23" до следующего звонка,
//   • под countdown — подпись "до следующего звонка",
//   • рядом мини-индикатор "Прогрессив · 2-й поспать ещё",
//   • в шапке плашка показывает обновлённый баланс с пометкой "−50 ₽",
//   • CTA: цена выросла до 100 ₽, в подсказке — следующая ступень 200 ₽,
//   • вторичная кнопка "Я встал — выключить" — без изменений.
//
// Цветовая палитра берётся из FIRING_THEMES (тот же справочник, что и для
// исходного firing-экрана), так что каждый из 6 артбордов получает свой
// фон, акцентный цвет, glow, градиент колокольчика. Структура одинаковая.
//
// Размер: 390×844 (как остальные themed firing-экраны).

function FiringThemeSnoozed({
  theme = "dawn",
  snoozes = 1,       // сколько раз уже нажали "Отложить"
  balance = 790,     // после списания за первое откладывание
  lastCharge = 50,   // сколько списано последним нажатием
  countdown = "04:23"// промежуточное состояние countdown'а (статика)
} = {}) {
  const t = FIRING_THEMES[theme] || FIRING_THEMES.dawn;

  // Прогрессивная шкала — та же, что в FiringDawnV3.
  const prices = [50, 100, 200, 400];
  const currentIdx = Math.min(snoozes, prices.length - 1);
  const currentPrice = prices[currentIdx];
  const nextPrice = currentIdx < prices.length - 1 ? prices[currentIdx + 1] : null;

  // На какое время сдвинулся будильник (07:00 + 5 мин × snoozes).
  const nextRingMin = snoozes * 5;
  const nextRing = `07:${String(nextRingMin).padStart(2, "0")}`;

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* Theme bg + scrim + локальный glow внизу. */}
      <div aria-hidden style={{ position: "absolute", inset: 0, background: t.bg }} />
      <div aria-hidden style={{ position: "absolute", inset: 0, background: t.scrim, pointerEvents: "none" }} />
      <div aria-hidden style={{
        position: "absolute", left: "50%", bottom: "-160px",
        transform: "translateX(-50%)",
        width: 460, height: 460, borderRadius: "50%",
        background: `radial-gradient(circle, ${t.accentSoft} 0%, transparent 65%)`,
        filter: "blur(24px)",
        pointerEvents: "none"
      }} />

      <SPStatusBar time={nextRing} tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* ============ HEADER ============ */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span className="sp-caps" style={{ color: "rgba(255,255,255,.55)" }}>Пт · 27 апр</span>
          <div className="dawn-bal" style={{
            color: t.accent,
            background: t.pillBg,
            borderColor: t.pillBorder
          }}>
            <IconCoin size={12} />
            <span className="dawn-bal__label" style={{ color: t.accent, opacity: .85 }}>Баланс</span>
            <span className="dawn-bal__value" style={{ color: t.accent }}>{balance} ₽</span>
          </div>
        </div>

        {/* ============ CENTER ============ */}
        <div style={{
          flex: 1, display: "flex", flexDirection: "column",
          justifyContent: "center", alignItems: "center",
          padding: "0 24px 16px", textAlign: "center", gap: 12
        }}>
          {/* Bell — приглушённый (откладываем, звонок временно затих). */}
          <div style={{
            position: "relative",
            width: 72, height: 72, borderRadius: 22,
            background: t.bellGrad,
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: `0 0 0 6px ${t.accentSoft}, 0 12px 36px rgba(0,0,0,.35)`,
            opacity: .7,
            marginBottom: 4
          }}>
            <IconBell size={32} style={{ color: "rgba(0,0,0,.7)", strokeWidth: 2 }} />
            {/* zZ маркер — тихий момент между звонками. */}
            <div style={{
              position: "absolute", right: -6, top: -8,
              padding: "2px 8px", borderRadius: 999,
              background: "rgba(0,0,0,.55)",
              border: `1px solid ${t.pillBorder}`,
              color: t.accent,
              font: "700 10px/14px var(--sp-font-mono)",
              letterSpacing: ".06em"
            }}>
              zZ
            </div>
          </div>

          {/* Alarm name + куда сдвинули звонок */}
          <div style={{
            font: "var(--sp-t-h3)",
            color: "rgba(255,255,255,.92)",
            letterSpacing: "-.01em"
          }}>
            Будни · отложено до {nextRing}
          </div>

          {/* HUGE countdown — заменяет большой клок. */}
          <div style={{
            font: "var(--sp-t-clock-xl)",
            color: "#FFF",
            letterSpacing: "-.05em",
            fontVariantNumeric: "tabular-nums",
            textShadow: t.timeShadow,
            marginTop: 4
          }}>
            {countdown}
          </div>

          {/* Прогрессивный индикатор + ticker уже списанного. */}
          <div style={{ marginTop: 14, display: "inline-flex", alignItems: "center", gap: 8, padding: "6px 12px", borderRadius: 999, background: "rgba(244,82,63,.14)", border: "1px solid rgba(244,82,63,.28)" }}>
            <span style={{
              display: "inline-block", width: 8, height: 8, borderRadius: 4,
              background: "rgba(244,82,63,.85)",
              boxShadow: "0 0 12px rgba(244,82,63,.6)"
            }} />
            <span className="sp-caps" style={{ color: "var(--sp-pain-300)", letterSpacing: ".18em" }}>
              Прогрессив · {snoozes + 1}-й поспать ещё
            </span>
          </div>

          {/* Ticker списаний — точки-ступени с суммами под ними. */}
          <div style={{ marginTop: 16, display: "flex", gap: 8, alignItems: "center" }}>
            {prices.map((p, i) => {
              const done = i < snoozes;
              const current = i === snoozes;
              return (
                <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
                  <span style={{
                    fontFamily: "var(--sp-font-mono)",
                    fontWeight: 700,
                    fontSize: 11,
                    color: done ? "var(--sp-pain-300)" : current ? t.accent : "rgba(255,255,255,.32)",
                    letterSpacing: 0
                  }}>
                    {p}
                  </span>
                  <span style={{
                    width: done ? 28 : 10, height: 4, borderRadius: 2,
                    background: done
                      ? "var(--sp-pain-400)"
                      : current
                        ? t.accent
                        : "rgba(255,255,255,.15)",
                    transition: "width 200ms ease"
                  }} />
                </div>
              );
            })}
          </div>
        </div>

        {/* ============ CTA ============ */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 10 }}>
          <button className="dawn-snooze dawn-snooze--warn" type="button">
            <div className="dawn-snooze__caps">
              <IconClock size={14} />
              Спать ещё 5 мин
            </div>
            <div className="dawn-snooze__price">
              −{currentPrice}<span className="dawn-snooze__cur">₽</span>
            </div>
            <div className="dawn-snooze__hint">
              {nextPrice
                ? `следующее откладывание: ${nextPrice} ₽`
                : "максимум — дальше только встать"}
            </div>
          </button>
          <button
            type="button"
            className="dawn-wake"
            style={{
              background: "transparent",
              color: "rgba(255,255,255,.92)",
              border: "1.5px solid rgba(255,255,255,.22)",
              boxShadow: "none",
              display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
              height: 56, borderRadius: 18, cursor: "pointer",
              font: "600 16px/20px var(--sp-font-body)"
            }}
          >
            <IconCheck size={18} />
            Я встал — выключить
          </button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FiringThemeSnoozed });
