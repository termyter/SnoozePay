// SnoozePay — адаптивные версии экранов онбординга 02/03/04
// для iPhone SE (375×667 pt). Та же визуальная система,
// что и у full-size версий (Onboarding1/2/3 в SPMore.jsx),
// но компактнее: уменьшены отступы, размеры заголовков,
// часы на экране 02, плотность карточек на 03 и 04.
//
// Цель — контент полностью помещается без скролла.

const { useState: seS } = React;

/* ────────────────────────────────────────────────────────────
   OnboardingSkipSE — pill «Пропустить».
   Чуть ближе к статус-бару (top 40 вместо 70), потому что
   статус-бар SE короче (нет dynamic island / notch).
   ──────────────────────────────────────────────────────────── */
function OnboardingSkipSE() {
  return (
    <button style={{
      position: "absolute",
      top: 30, right: 14,
      zIndex: 5,
      padding: "5px 12px",
      border: "1px solid var(--sp-white-08)",
      borderRadius: 999,
      background: "var(--sp-white-06)",
      cursor: "pointer",
      font: "12px/16px var(--sp-font-body)",
      fontWeight: 700,
      color: "var(--sp-fg-3)",
    }}>Пропустить</button>
  );
}

/* ============================================================
   02 · Onboarding 1/3 — «Будильник со ставкой» (SE)
   Адаптации:
   – paddingTop 44 (короче статус-бар у SE)
   – часы 72px (было 96)
   – заголовок h2 24/32 (было h1 32/40)
   – body 15/22 (было 17/26)
   – ширина body 240 (было 280)
   ============================================================ */
function Onboarding1SE() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <div style={{
        position: "absolute", left: "50%", top: 40, transform: "translateX(-50%)",
        width: 340, height: 340, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.25) 0%, transparent 60%)", filter: "blur(40px)",
      }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <OnboardingSkipSE/>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", padding: "44px 16px 20px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center" }}>
          <div style={{ fontSize: 72, lineHeight: 1, fontFamily: "var(--sp-font-mono)", color: "#FFF", letterSpacing: "-.05em", fontWeight: 200 }}>
            07:00
          </div>
          <div style={{
            marginTop: 14, padding: "6px 10px", borderRadius: 999,
            background: "var(--sp-grad-warn)", color: "var(--sp-fg-on-warn)",
            font: "12px/16px var(--sp-font-mono)", fontWeight: 700,
            display: "inline-flex", boxShadow: "0 8px 24px rgba(245,158,11,.30)",
          }}>−{fmtRub(50)}</div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 24, letterSpacing: "-.02em" }}>
            Будильник<br/>со ставкой
          </div>
          <div style={{ font: "var(--sp-t-body)", color: "var(--sp-fg-2)", marginTop: 10, maxWidth: 240 }}>
            Каждое откладывание стоит денег. Деньги не вернутся. Зато вы встанете.
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, marginBottom: 14 }}>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
        </div>
        <SPButton variant="money" size="lg" full>Дальше</SPButton>
      </div>
    </div>
  );
}

/* ============================================================
   03 · Onboarding 2/3 — «Как это работает» (SE)
   Адаптации:
   – paddingTop 44, paddingBottom 20
   – заголовок h2 (24/32) → две строки помещаются по высоте
   – маркер цифры 28×28 (было 32×32)
   – meta-текст 12/16 (плотнее, лучше для маленького экрана)
   – gap между шагами 12 (было 14)
   ============================================================ */
function Onboarding2SE() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <OnboardingSkipSE/>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", padding: "44px 16px 20px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>как это работает</div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 6, letterSpacing: "-.02em" }}>
            Положи баланс.<br/>Откладывай — теряй.
          </div>
          <div style={{ marginTop: 22, display: "flex", flexDirection: "column", gap: 12 }}>
            {[
              { n: "1", t: "Положили 500 ₽", s: "Это запас, из которого спишутся штрафы." },
              { n: "2", t: "Поспать ещё в 07:00 → −50 ₽", s: "Каждый раз когда вы тянете, деньги уходят." },
              { n: "3", t: "Встали с первого раза → ничего", s: "Баланс лежит. Готов к завтрашнему утру." },
            ].map((row, i) => (
              <div key={i} style={{ display: "flex", gap: 12, alignItems: "flex-start" }}>
                <div style={{
                  width: 28, height: 28, borderRadius: 8, flexShrink: 0,
                  background: "var(--sp-white-08)", color: "var(--sp-fg-2)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  font: "13px/16px var(--sp-font-mono)", fontWeight: 700,
                }}>{row.n}</div>
                <div style={{ paddingTop: 1 }}>
                  <div style={{ font: "700 15px/20px var(--sp-font-display)", color: "#FFF" }}>{row.t}</div>
                  <div style={{ font: "500 12px/16px var(--sp-font-body)", color: "var(--sp-fg-2)", marginTop: 2 }}>{row.s}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, marginBottom: 14 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
        </div>
        <SPButton variant="money" size="lg" full>Дальше</SPButton>
      </div>
    </div>
  );
}

/* ============================================================
   04 · Onboarding 3/3 — «Стартовый депозит» (SE)
   Адаптации:
   – paddingTop 44, paddingBottom 14
   – заголовок h2 (24/32)
   – карточки депозита: padding 12×14 (было 16×20)
   – radius 14 (было 18)
   – gap между карточками 6 (было 8)
   – суммы money-sm (14px) на главной строке вместо money-md
   – meta 11/14 — плотнее, всё всё ещё читается
   ============================================================ */
function Onboarding3SE() {
  const [v, setV] = seS(500);
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <div style={{
        position: "absolute", top: -120, left: -60,
        width: 280, height: 280, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.25) 0%, transparent 60%)", filter: "blur(40px)",
      }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <OnboardingSkipSE/>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", padding: "44px 16px 14px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>баланс · сколько положить</div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 6, letterSpacing: "-.02em" }}>
            Сколько ставите<br/>на свою дисциплину?
          </div>
          <div style={{ marginTop: 18, display: "flex", flexDirection: "column", gap: 6 }}>
            {[
              { v: 250, t: "Попробовать", s: "≈ 5 откладываний по 50 ₽" },
              { v: 500, t: "Серьёзно",     s: "≈ 10 откладываний · 2 недели", popular: true },
              { v: 1000, t: "Решительно",  s: "≈ 20 откладываний · месяц" },
            ].map(o => {
              const sel = v === o.v;
              return (
                <button key={o.v} onClick={()=>setV(o.v)} style={{
                  width: "100%", padding: "12px 14px", borderRadius: 14, cursor: "pointer", textAlign: "left",
                  background: sel ? "linear-gradient(135deg, rgba(46,219,159,.12), rgba(46,219,159,.04))" : "var(--sp-white-06)",
                  border: sel ? "1px solid rgba(46,219,159,.40)" : "1px solid var(--sp-white-08)",
                  color: "#FFF", display: "flex", alignItems: "center", justifyContent: "space-between",
                  gap: 10,
                  position: "relative", transition: "all 160ms var(--sp-ease-out)",
                }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <span style={{ font: "700 15px/20px var(--sp-font-display)", color: "#FFF" }}>{o.t}</span>
                      {o.popular && <span style={{ font: "9px/12px var(--sp-font-body)", fontWeight: 700, color: "var(--sp-money-300)", letterSpacing: ".12em", textTransform: "uppercase" }}>популярно</span>}
                    </div>
                    <div style={{ font: "500 11px/14px var(--sp-font-body)", color: "var(--sp-fg-3)", marginTop: 2 }}>{o.s}</div>
                  </div>
                  <div style={{
                    font: "700 17px/22px var(--sp-font-mono)",
                    color: sel ? "var(--sp-money-300)" : "var(--sp-fg-1)",
                    fontVariantNumeric: "tabular-nums",
                    whiteSpace: "nowrap",
                    flexShrink: 0,
                  }}>
                    {o.v} ₽
                  </div>
                </button>
              );
            })}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, marginBottom: 10 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
        </div>
        <SPButton variant="money" size="lg" full icon={<IconWallet size={20}/>} suffix={fmtRubTight(v)}>Пополнить</SPButton>
        <button style={{
          width: "100%", border: 0, background: "transparent", padding: "4px 0 0",
          font: "700 13px/18px var(--sp-font-body)", color: "var(--sp-fg-3)", cursor: "pointer",
        }}>Позже — попробовать без баланса</button>
      </div>
    </div>
  );
}

Object.assign(window, {
  Onboarding1SE, Onboarding2SE, Onboarding3SE,
});
