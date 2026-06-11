// SnoozePay · Firing Theme — состояние «БАЛАНС ЗАКОНЧИЛСЯ».
//
// Будильник звонит, но на штрафы за откладывание денег больше нет.
// Откладывать нельзя — карточка «Поспать ещё» заблокирована,
// единственные действия: пополнить баланс или встать.
//
// Отличия от обычного firing-экрана и от состояния «После Отложить»:
//   • большое «07:00» (это balance-out стейт, не countdown),
//   • красная пилюля баланса «⊘ Баланс 0 ₽» — во ВСЕХ темах,
//   • красная пилюля «БАЛАНСА НЕ ОСТАЛОСЬ» под временем,
//   • НЕТ прогрессивной шкалы (откладывать невозможно),
//   • карточка «Поспать ещё» — нейтрально-серая, disabled,
//   • зелёная кнопка «Пополнить 500 ₽» — главное действие, зелёная везде,
//   • стеклянная «Я встал — выключить» — рамка цвета темы,
//   • нижний glow — красноватый/«drained», медленное дыхание 8 с.
//
// Меняется ТОЛЬКО фон-градиент (desaturated/cooler версия темы) и
// акцент рамки/иконки стеклянной кнопки. Все «тревожные» элементы
// (красные пилюли, зелёная кнопка, красный glow) одинаковы во всех 6.
//
// Размер: 390×844 (как остальные themed firing-экраны).

/* Desaturated / cooler палитра — «выкачанный» баланс.
   bg     — приглушённый фон-градиент темы
   accent — акцент рамки стеклянной кнопки + caps-даты */
const DRAINED_THEMES = {
  dawn: {
    name: "Рассвет",
    bg: "linear-gradient(160deg, #41290F 0%, #804F1E 50%, #CE8A30 100%)",
    accent: "#FAD89A",
  },
  ocean: {
    name: "Океан",
    bg: "linear-gradient(160deg, #11324C 0%, #266384 50%, #4DA597 100%)",
    accent: "#B4ECD8",
  },
  mountain: {
    name: "Горы",
    bg: "linear-gradient(160deg, #28313F 0%, #586A92 50%, #AAB5CB 100%)",
    accent: "#DEE3EB",
  },
  forest: {
    name: "Лес",
    bg: "linear-gradient(160deg, #0E250E 0%, #2A4C30 50%, #4D7340 100%)",
    accent: "#B6DEA0",
  },
  neon: {
    name: "Неон",
    bg: "linear-gradient(160deg, #1A1648 0%, #582A90 50%, #CE469E 100%)",
    accent: "#F4A6D2",
  },
  abstract: {
    name: "Абстракт",
    bg: "linear-gradient(160deg, #26262A 0%, #47474F 100%)",
    accent: "#DADADA",
  },
};

function FiringThemeNoBalance({ theme = "dawn" } = {}) {
  const t = DRAINED_THEMES[theme] || DRAINED_THEMES.dawn;

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* Desaturated theme bg. */}
      <div aria-hidden style={{ position: "absolute", inset: 0, background: t.bg }} />
      {/* Тёмный scrim — притапливает фон, держит контраст текста. */}
      <div aria-hidden style={{
        position: "absolute", inset: 0,
        background: "radial-gradient(120% 80% at 50% 40%, rgba(0,0,0,0) 0%, rgba(0,0,0,.34) 100%)",
        pointerEvents: "none"
      }} />
      {/* Красноватый «drained» glow снизу — медленное дыхание 8 с. */}
      <div aria-hidden style={{
        position: "absolute", left: "50%", bottom: "-170px",
        transform: "translateX(-50%)",
        width: 480, height: 480, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(244,82,63,.28) 0%, rgba(244,82,63,.08) 40%, transparent 68%)",
        filter: "blur(26px)",
        pointerEvents: "none",
        animation: "dawn-breathe 8s ease-in-out infinite"
      }} />

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* ============ HEADER ============ */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span className="sp-caps" style={{ color: t.accent, opacity: .65 }}>Пт · 27 апр</span>
          {/* Баланс 0 — красная пилюля во ВСЕХ темах. */}
          <div className="dawn-bal is-lost">
            <IconCoinOff size={12} />
            <span className="dawn-bal__label">Баланс</span>
            <span className="dawn-bal__value">0 ₽</span>
          </div>
        </div>

        {/* ============ CENTER ============ */}
        <div style={{
          flex: 1, display: "flex", flexDirection: "column",
          justifyContent: "center", alignItems: "center",
          padding: "0 24px 8px", textAlign: "center"
        }}>
          {/* Большое время — balance-out, НЕ countdown. */}
          <div style={{
            font: "var(--sp-t-clock-xl)",
            color: "#FFF",
            letterSpacing: "-.05em",
            fontVariantNumeric: "tabular-nums",
            textShadow: "0 4px 60px rgba(0,0,0,.45)"
          }}>
            07:00
          </div>

          {/* Красная пилюля — баланса не осталось. */}
          <div style={{
            marginTop: 22, padding: "8px 14px", borderRadius: 999,
            background: "rgba(244,82,63,.16)",
            border: "1px solid rgba(244,82,63,.34)",
            display: "inline-flex", alignItems: "center", gap: 8
          }}>
            <IconCoinOff size={14} style={{ color: "var(--sp-pain-300)" }} />
            <span className="sp-caps" style={{ color: "var(--sp-pain-300)", letterSpacing: ".16em" }}>
              Баланса не осталось
            </span>
          </div>

          {/* Поясняющий текст — 2 строки, приглушённый белый. */}
          <div style={{
            marginTop: 16, maxWidth: 250,
            color: "rgba(255,255,255,.72)",
            font: "var(--sp-t-body-lg)"
          }}>
            Откладывать больше не получится. Только встать.
          </div>
        </div>

        {/* ============ ACTIONS ============ */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 10 }}>

          {/* «Поспать ещё» — DISABLED, нейтрально-серая, без glow/пульсации. */}
          <div style={{
            position: "relative",
            width: "100%", padding: "16px 20px", borderRadius: 18,
            background: "rgba(255,255,255,.05)",
            border: "1px solid rgba(255,255,255,.08)",
            display: "flex", flexDirection: "column", alignItems: "center", gap: 2,
            opacity: .5, filter: "grayscale(1)", cursor: "not-allowed",
            textAlign: "center"
          }}>
            <div style={{
              display: "inline-flex", alignItems: "center", gap: 6,
              font: "var(--sp-t-caps)", letterSpacing: ".14em",
              color: "rgba(255,255,255,.6)"
            }}>
              <IconClock size={14} />
              Спать ещё 5 мин
            </div>
            <div style={{
              font: "700 32px/36px var(--sp-font-mono)",
              color: "rgba(255,255,255,.55)",
              letterSpacing: "-.02em", fontVariantNumeric: "tabular-nums"
            }}>
              −50<span style={{ paddingLeft: ".25em" }}>₽</span>
            </div>
            <div style={{ font: "500 12px/14px var(--sp-font-body)", color: "rgba(255,255,255,.5)" }}>
              Недостаточно средств
            </div>
          </div>

          {/* «Пополнить 500 ₽» — зелёная, главное действие, во всех темах. */}
          <SPButton variant="money" size="lg" full icon={<IconWallet size={20} />} suffix={fmtRubTight(500)}>
            Пополнить
          </SPButton>

          {/* «Я встал — выключить» — стеклянная, рамка цвета темы. */}
          <button
            type="button"
            className="dawn-wake"
            style={{
              background: "transparent",
              color: "rgba(255,255,255,.92)",
              border: `1.5px solid ${t.accent}`,
              boxShadow: "none",
              opacity: .9
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

Object.assign(window, { FiringThemeNoBalance });
