// SnoozePay — экран «Пополнение баланса» (375×667 SE).
// Открывается из вкладки «Кошелёк» или из главного «Пополнить».
// CTA запускает нативный Google Play Billing — поэтому в самом
// экране НЕТ способов оплаты, только выбор суммы.
//
// Визуальная преемственность с Onboarding 3/3 (стартовый депозит):
// та же сетка 250/500/1000, такие же money-карточки выбора,
// но добавлен Hero с текущим балансом и Top-bar «Назад».

const { useState: tuS } = React;

/* ────────────────────────────────────────────────────────────
   Иконка щита-молнии для info-стрипа.
   Намеренно не используем стандартный IconShield —
   эта версия с молнией внутри читается как «быстро / безопасно
   через Google Play», что точнее отражает суть подписи.
   ──────────────────────────────────────────────────────────── */
function IconShieldBolt({ size = 20, color = "var(--sp-money-400)" }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke={color} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 3l8 4v6c0 4-3 7-8 8-5-1-8-4-8-8V7l8-4z"/>
      <path d="M13 8l-3 5h3l-1 4 3-5h-3l1-4z" fill={color} stroke={color} strokeWidth="1"/>
    </svg>
  );
}

/* ────────────────────────────────────────────────────────────
   TopUpSE — пополнение, SE-формат (375×667)
   props:
   – balance: текущий баланс в ₽ (число). 0 = первое пополнение.
   ──────────────────────────────────────────────────────────── */
function TopUpSE({ balance = 0 }) {
  const [v, setV] = tuS(500);

  const presets = [
    { v: 250,  t: "Попробовать", s: "≈ 5 откладываний · одна неделя" },
    { v: 500,  t: "Серьёзно",     s: "≈ 10 откладываний · две недели", popular: true },
    { v: 1000, t: "Решительно",   s: "≈ 20 откладываний · спокойный месяц" },
  ];

  const isZero = balance === 0;

  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      {/* Тонкое money-свечение сверху-слева — намекает на pending пополнение.
          Не перекрывает Hero, потому что лежит за статус-баром. */}
      <div style={{
        position: "absolute", top: -110, left: -60,
        width: 260, height: 260, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.22) 0%, transparent 60%)",
        filter: "blur(40px)",
      }}/>
      <SPStatusBar time="9:42" tone="light"/>

      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", padding: "44px 16px 20px" }}>

        {/* ─── 1. Top bar ─────────────────────────────────── */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", height: 28 }}>
          <button style={{
            display: "flex", alignItems: "center", gap: 2,
            border: 0, background: "transparent", padding: "4px 4px 4px 0",
            cursor: "pointer", color: "var(--sp-money-300)",
            font: "500 15/22 var(--sp-font-body)",
          }}>
            <IconBack size={20}/>
            <span style={{ font: "var(--sp-t-body)", color: "var(--sp-money-300)" }}>Назад</span>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>пополнение</div>
          <div style={{ width: 64 }} aria-hidden="true"/>
        </div>

        {/* ─── 2. Hero — текущий баланс ───────────────────── */}
        <div style={{ marginTop: 18 }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>текущий баланс</div>
          <div style={{
            font: "var(--sp-t-money-lg)",
            color: isZero ? "var(--sp-fg-4)" : "var(--sp-money-300)",
            letterSpacing: "-.02em", fontVariantNumeric: "tabular-nums",
            marginTop: 4,
          }}>
            {balance} ₽
          </div>
          {!isZero && (
            <div style={{ font: "500 12px/16px var(--sp-font-body)", color: "var(--sp-fg-3)", marginTop: 2 }}>
              Хватит на ~{Math.floor(balance/50)} откладываний по 50 ₽
            </div>
          )}
          {isZero && (
            <div style={{ font: "500 12px/16px var(--sp-font-body)", color: "var(--sp-fg-3)", marginTop: 2 }}>
              Залога ещё нет — положите, чтобы будильник заработал.
            </div>
          )}
        </div>

        {/* ─── 3. Сепаратор ───────────────────────────────── */}
        <div className="sp-caps" style={{ color: "var(--sp-money-300)", marginTop: 18 }}>
          сколько положить
        </div>

        {/* ─── 4. Deposit presets ─────────────────────────── */}
        <div style={{ marginTop: 10, display: "flex", flexDirection: "column", gap: 8 }}>
          {presets.map(o => {
            const sel = v === o.v;
            return (
              <button key={o.v} onClick={() => setV(o.v)} style={{
                width: "100%", padding: "12px 14px", borderRadius: 16, cursor: "pointer", textAlign: "left",
                background: sel
                  ? "linear-gradient(135deg, rgba(46,219,159,.16), rgba(46,219,159,.04))"
                  : "var(--sp-white-06)",
                border: sel ? "1.5px solid rgba(46,219,159,.55)" : "1px solid var(--sp-white-08)",
                color: "#FFF", display: "flex", alignItems: "center", justifyContent: "space-between",
                gap: 10, position: "relative",
                transition: "all 160ms var(--sp-ease-out)",
              }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ font: "700 15px/20px var(--sp-font-display)", color: "#FFF" }}>{o.t}</span>
                    {o.popular && (
                      <span style={{
                        font: "9px/12px var(--sp-font-body)", fontWeight: 700,
                        color: "var(--sp-money-300)", letterSpacing: ".12em", textTransform: "uppercase",
                      }}>популярно</span>
                    )}
                  </div>
                  <div style={{ font: "500 11px/14px var(--sp-font-body)", color: "var(--sp-fg-3)", marginTop: 2 }}>
                    {o.s}
                  </div>
                </div>

                {/* RIGHT cluster: amount + (selected) money-check */}
                <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                  <div style={{
                    font: "700 17px/22px var(--sp-font-mono)",
                    color: sel ? "var(--sp-money-300)" : "var(--sp-fg-1)",
                    fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
                  }}>
                    {o.v} ₽
                  </div>
                  {sel && (
                    <div style={{
                      width: 22, height: 22, borderRadius: "50%",
                      background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
                      display: "flex", alignItems: "center", justifyContent: "center",
                      flexShrink: 0,
                      boxShadow: "0 4px 12px rgba(46,219,159,.30)",
                    }}>
                      <IconCheck size={14}/>
                    </div>
                  )}
                </div>
              </button>
            );
          })}
        </div>

        {/* ─── Spacer — толкает info-стрип и CTA к низу ───── */}
        <div style={{ flex: 1 }} aria-hidden="true"/>

        {/* ─── 5. Info стрип ──────────────────────────────── */}
        <div style={{
          display: "flex", alignItems: "flex-start", gap: 10,
          padding: "10px 12px", borderRadius: 12,
          background: "var(--sp-white-06)", border: "1px solid var(--sp-white-08)",
          marginBottom: 12,
        }}>
          <div style={{ flexShrink: 0, paddingTop: 1 }}>
            <IconShieldBolt size={18}/>
          </div>
          <div style={{ font: "500 12px/16px var(--sp-font-body)", color: "var(--sp-fg-2)" }}>
            Оплата через Google Play. Можно отменить в любой момент в настройках подписок.
          </div>
        </div>

        {/* ─── 6. CTA ─────────────────────────────────────── */}
        <SPButton variant="money" size="lg" full icon={<IconWallet size={20}/>} suffix={`${v} ₽`}>
          Пополнить
        </SPButton>
      </div>
    </div>
  );
}

Object.assign(window, { TopUpSE });
