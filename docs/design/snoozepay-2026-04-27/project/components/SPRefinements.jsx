// SnoozePay — финальные правки firing-экранов
// FiringDawnProgressive — 3 стейджа покраснения (1, 4, 7-е откладывание)
// FiringNoBalanceV3 — другой цвет + кнопка "Пополнить" доминирует

const { useState: fdS } = React;

/* ============================================================
   FIRING — Прогрессив (постепенное покраснение)
   Стейджи: 1 (тёплый), 4 (янтарь→красный), 7 (полный pain)
   ============================================================ */
function FiringDawnProgressive({ stage = 1 }) {
  // Цена и палитра по стейджу
  const cfg = stage <= 1
    ? { price: 50,  bgFrom: "#0E1320", bgVia: "#2B1A0E", bgTo: "#4A2410", glow: "rgba(255,184,77,.30)", tone: "warn",   label: "1-е откладывание", priceColor: "var(--sp-warn-400)", capsColor: "var(--sp-warn-300)" }
    : stage === 4
    ? { price: 200, bgFrom: "#0E1320", bgVia: "#3A1A14", bgTo: "#6B2410", glow: "rgba(255,120,77,.45)", tone: "warn",   label: "4-е откладывание · цена ×4", priceColor: "var(--sp-warn-400)", capsColor: "var(--sp-warn-300)" }
    : { price: 800, bgFrom: "#0E1320", bgVia: "#4A0E14", bgTo: "#7A1818", glow: "rgba(244,82,63,.55)",  tone: "pain",   label: "7-е откладывание · последний шанс", priceColor: "var(--sp-pain-400)", capsColor: "var(--sp-pain-400)" };

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden",
      background: `linear-gradient(180deg, ${cfg.bgFrom} 0%, ${cfg.bgVia} 60%, ${cfg.bgTo} 100%)`,
      transition: "background 600ms ease" }}>
      <div style={{ position: "absolute", left: "50%", bottom: "-30%", transform: "translateX(-50%)",
        width: 520, height: 520, borderRadius: "50%",
        background: `radial-gradient(circle, ${cfg.glow} 0%, transparent 60%)`, filter: "blur(40px)" }}/>

      <SPStatusBar time="7:14" tone="light"/>

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, padding: "54px 24px 32px",
        display: "flex", flexDirection: "column" }}>
        {/* Stage indicator — 7 точек */}
        <div style={{ display: "flex", gap: 4, paddingTop: 12 }}>
          {Array.from({length: 7}).map((_, i) => (
            <div key={i} style={{
              flex: 1, height: 3, borderRadius: 2,
              background: i < stage ? (stage >= 7 ? "var(--sp-pain-400)" : "var(--sp-warn-400)") : "var(--sp-white-12)",
              transition: "background 400ms"
            }}/>
          ))}
        </div>

        <div style={{ marginTop: 16 }}>
          <div className="sp-caps" style={{ color: cfg.capsColor }}>{cfg.label}</div>
          <div style={{ font: "200 96px/96px var(--sp-font-mono)", color: "#FFF",
            letterSpacing: "-.04em", marginTop: 8, fontVariantNumeric: "tabular-nums" }}>7:14</div>
          <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 8 }}>
            Будни · Понедельник
          </div>
        </div>

        <div style={{ flex: 1 }}/>

        {/* Кнопка откладывания с растущей ценой */}
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <button style={{
            width: "100%", padding: "22px 24px", borderRadius: 24, cursor: "pointer",
            background: stage >= 7
              ? "linear-gradient(135deg, var(--sp-pain-500), var(--sp-pain-400))"
              : "linear-gradient(135deg, rgba(245,158,11,.18), rgba(245,158,11,.06))",
            border: stage >= 7 ? "0" : "1px solid rgba(245,158,11,.40)",
            display: "flex", alignItems: "center", justifyContent: "space-between",
            transition: "all 400ms ease",
          }}>
            <div style={{ textAlign: "left" }}>
              <div className="sp-caps" style={{ color: stage >= 7 ? "rgba(255,255,255,.85)" : cfg.capsColor }}>Поспать ещё · +9 минут</div>
              <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                {cfg.price} ₽
              </div>
            </div>
            <IconChevR size={22} style={{ color: "#FFF" }}/>
          </button>

          <SPButton variant={stage >= 7 ? "money" : "quiet"} size="lg" full>
            {stage >= 7 ? "Встать (бесплатно)" : "Встать"}
          </SPButton>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   FIRING — No balance v3
   Кнопка "Пополнить" — главное действие, другой цвет (синий — money tone)
   ============================================================ */
function FiringNoBalanceV3() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden",
      background: "linear-gradient(180deg, #0A1628 0%, #0E2A40 60%, #0F3D5C 100%)" }}>
      {/* Холодное синее свечение — чужое, не Dawn */}
      <div style={{ position: "absolute", left: "50%", bottom: "-30%", transform: "translateX(-50%)",
        width: 520, height: 520, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.30) 0%, transparent 60%)", filter: "blur(40px)" }}/>

      <SPStatusBar time="7:14" tone="light"/>

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, padding: "54px 24px 32px",
        display: "flex", flexDirection: "column" }}>

        <div style={{ paddingTop: 16 }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Будни · Понедельник</div>
          <div style={{ font: "200 96px/96px var(--sp-font-mono)", color: "rgba(255,255,255,.85)",
            letterSpacing: "-.04em", marginTop: 8, fontVariantNumeric: "tabular-nums" }}>7:14</div>
        </div>

        {/* Hero — баланс 0 */}
        <div style={{ marginTop: 32, padding: 20, borderRadius: 20,
          background: "rgba(255,255,255,.04)", border: "1px solid var(--sp-white-08)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Баланс</div>
            <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-fg-3)",
              fontVariantNumeric: "tabular-nums" }}>0 ₽</div>
          </div>
          <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 12 }}>
            Чтобы поспать ещё, нужно пополнить баланс. Без него — только встать.
          </div>
        </div>

        <div style={{ flex: 1 }}/>

        {/* Кнопка пополнить — main action, money-tone, доминирует */}
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <button style={{
            width: "100%", padding: "20px 24px", borderRadius: 20, border: 0, cursor: "pointer",
            background: "var(--sp-grad-money)",
            color: "var(--sp-fg-on-money)",
            display: "flex", alignItems: "center", justifyContent: "space-between",
            boxShadow: "0 12px 32px rgba(43,194,140,.40)",
          }}>
            <div style={{ textAlign: "left" }}>
              <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-on-money)" }}>Пополнить и поспать ещё</div>
              <div className="sp-meta" style={{ color: "rgba(5,32,22,.7)", marginTop: 2 }}>
                Apple Pay · от 200 ₽
              </div>
            </div>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.05 12.04c-.03-2.95 2.41-4.37 2.52-4.44-1.37-2.01-3.51-2.29-4.27-2.32-1.82-.18-3.55 1.07-4.48 1.07-.94 0-2.36-1.04-3.88-1.01-2 .03-3.84 1.16-4.86 2.95-2.07 3.59-.53 8.91 1.49 11.83.99 1.43 2.16 3.03 3.69 2.97 1.48-.06 2.04-.96 3.83-.96 1.78 0 2.29.96 3.85.93 1.59-.03 2.6-1.45 3.57-2.89 1.13-1.66 1.59-3.27 1.62-3.35-.04-.02-3.11-1.19-3.14-4.78zM14.13 4.27c.81-.99 1.36-2.36 1.21-3.72-1.17.05-2.59.78-3.43 1.76-.75.87-1.41 2.27-1.24 3.6 1.31.1 2.65-.66 3.46-1.64z"/>
            </svg>
          </button>

          <SPButton variant="quiet" size="md" full>Встать без откладываний</SPButton>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   REFERRAL v2 — добавлен ввод кода друга
   ============================================================ */
function ReferralV2() {
  const [code, setCode] = fdS("");
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)",
            color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Пригласить</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "16px 20px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Hero */}
          <div style={{ position: "relative", borderRadius: 24, overflow: "hidden", padding: 28,
            background: "linear-gradient(135deg, #1A2810 0%, #2C4A1F 50%, #4F8A3A 100%)" }}>
            <div style={{ position: "absolute", right: -40, top: -40, width: 200, height: 200, borderRadius: "50%",
              background: "radial-gradient(circle, rgba(43,194,140,.40) 0%, transparent 60%)", filter: "blur(20px)" }}/>
            <div className="sp-caps" style={{ color: "rgba(255,255,255,.7)" }}>Реферальная программа</div>
            <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 8, letterSpacing: "-.02em" }}>
              +200 ₽ вам<br/>+200 ₽ другу
            </div>
            <div className="sp-body" style={{ color: "rgba(255,255,255,.85)", marginTop: 10 }}>
              Когда друг продержится 7 дней — оба получаете бонус в баланс.
            </div>
          </div>

          {/* Ваш код */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Ваш код</div>
            <SPCard padding={16} radius={16}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <div style={{ flex: 1, font: "20px/24px var(--sp-font-mono)", color: "#FFF",
                  letterSpacing: ".15em" }}>WAKEUP-7K2</div>
                <SPButton variant="money" size="sm">Копировать</SPButton>
              </div>
            </SPCard>
          </div>

          {/* НОВОЕ: ввод кода друга */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Есть код друга?</div>
            <SPCard padding={16} radius={16}>
              <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginBottom: 12 }}>
                Введите код, чтобы получить +200 ₽ к своему балансу. Друг тоже получит бонус.
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  value={code}
                  onChange={e => setCode(e.target.value.toUpperCase())}
                  placeholder="WAKEUP-XXX"
                  style={{
                    flex: 1, padding: "14px 16px", borderRadius: 12,
                    background: "var(--sp-white-06)", border: "1px solid var(--sp-white-08)",
                    color: "#FFF", font: "16px/20px var(--sp-font-mono)",
                    letterSpacing: ".1em", outline: "none",
                  }}
                />
                <SPButton variant={code ? "money" : "quiet"} size="md" disabled={!code}>Применить</SPButton>
              </div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 10 }}>
                Бонус активируется после 7 дней без срывов
              </div>
            </SPCard>
          </div>

          {/* Друзья */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 10 }}>Ваши друзья</div>
            <SPCard padding={4} radius={16}>
              <SPRow leading={
                <div style={{ width: 36, height: 36, borderRadius: 18, background: "var(--sp-grad-money)",
                  display: "flex", alignItems: "center", justifyContent: "center", font: "var(--sp-t-h4)", color: "var(--sp-fg-on-money)" }}>М</div>
              } title="Маша К." subtitle="Продержалась 7 дней"
                trailing={<span style={{font:"var(--sp-t-money-md)", color:"var(--sp-money-400)"}}>+200 ₽</span>}/>
              <SPRow leading={
                <div style={{ width: 36, height: 36, borderRadius: 18, background: "var(--sp-warn-700)",
                  display: "flex", alignItems: "center", justifyContent: "center", font: "var(--sp-t-h4)", color: "var(--sp-warn-300)" }}>Д</div>
              } title="Дима Р." subtitle="День 4 из 7"
                trailing={<span className="sp-meta" style={{color:"var(--sp-warn-400)"}}>скоро</span>}/>
              <SPRow divider={false} leading={
                <div style={{ width: 36, height: 36, borderRadius: 18, background: "var(--sp-white-08)",
                  display: "flex", alignItems: "center", justifyContent: "center", font: "var(--sp-t-h4)", color: "var(--sp-fg-3)" }}>А</div>
              } title="Аня С." subtitle="День 1 из 7"
                trailing={<span className="sp-meta" style={{color:"var(--sp-fg-3)"}}>в процессе</span>}/>
            </SPCard>
          </div>
        </div>

        <div style={{ padding: "0 20px 32px" }}>
          <SPButton variant="money" size="lg" full>Поделиться кодом</SPButton>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FiringDawnProgressive, FiringNoBalanceV3, ReferralV2 });
