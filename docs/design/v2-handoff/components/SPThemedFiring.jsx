// SnoozePay — firing-screen для каждой из 6 готовых тем.
// Тема меняет ТОЛЬКО фон (full-bleed визуал), затемнение для читаемости
// текста и тонирование "лёгких" акцентов (eyebrow, ring). Layout, текст,
// типографика, цены и кнопки идентичны на всех темах — это то же самое
// поведение, обёрнутое в разный визуал.
//
// Контент следует тому, что показывает интерактивный firing-screen
// (`FiringDawnV3`): статус-бар, дата + балансная плашка, большой клок,
// надпись "пора вставать", CTA "Спать ещё 5 мин · −50 ₽" и outline-кнопка
// "Я встал — выключить". Здесь — статичная превью-версия без интерактива.

/* ───── Каталог тем ─────
   Дублирует темы из ThemePicker (components/SPMore2.jsx) — id и градиенты
   совпадают, плюс параметры для firing-сцены:
     scrim       — затемняющий слой поверх фона, чтобы белый текст читался
     accent      — цвет ring'а на иконке будильника, eyebrow и balance pill
     accentSoft  — полупрозрачная заливка ring/glow
     timeShadow  — цветной soft glow вокруг времени (под тон темы)
     bellGrad    — градиент квадратной иконки колокольчика */
const FIRING_THEMES = {
  dawn: {
    name: "Рассвет",
    bg: "linear-gradient(160deg, #2B1A0E 0%, #6B3517 50%, #C46A1A 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,.05) 0%, rgba(0,0,0,.5) 100%)",
    accent: "#FFD479",
    accentSoft: "rgba(255,212,121,.18)",
    timeShadow: "0 4px 60px rgba(255,184,77,.35)",
    bellGrad: "linear-gradient(135deg, #FFD479 0%, #F59E0B 60%, #C97A06 100%)",
    pillBg: "rgba(255,184,77,.16)",
    pillBorder: "rgba(255,212,121,.32)",
  },
  ocean: {
    name: "Океан",
    bg: "linear-gradient(160deg, #08182A 0%, #134E5E 50%, #71B280 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,.05) 0%, rgba(0,0,0,.55) 100%)",
    accent: "#9EE6CC",
    accentSoft: "rgba(158,230,204,.18)",
    timeShadow: "0 4px 60px rgba(113,178,128,.32)",
    bellGrad: "linear-gradient(135deg, #9EE6CC 0%, #4A9D9C 60%, #1F5F66 100%)",
    pillBg: "rgba(113,178,128,.18)",
    pillBorder: "rgba(158,230,204,.32)",
  },
  mountain: {
    name: "Горы",
    bg: "linear-gradient(160deg, #1A1F2E 0%, #5A6B8A 50%, #E1E5EA 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,.10) 0%, rgba(0,0,0,.50) 100%)",
    accent: "#E1E5EA",
    accentSoft: "rgba(225,229,234,.20)",
    timeShadow: "0 4px 60px rgba(225,229,234,.30)",
    bellGrad: "linear-gradient(135deg, #F4F6F9 0%, #B7C0D0 60%, #5A6B8A 100%)",
    pillBg: "rgba(183,192,208,.22)",
    pillBorder: "rgba(225,229,234,.40)",
  },
  forest: {
    name: "Лес",
    bg: "linear-gradient(160deg, #0A1A0A 0%, #1E3823 50%, #4A6B3A 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,.05) 0%, rgba(0,0,0,.55) 100%)",
    accent: "#A8D89A",
    accentSoft: "rgba(168,216,154,.16)",
    timeShadow: "0 4px 60px rgba(74,107,58,.40)",
    bellGrad: "linear-gradient(135deg, #C5E8B0 0%, #6A9853 60%, #2F4D24 100%)",
    pillBg: "rgba(74,107,58,.22)",
    pillBorder: "rgba(168,216,154,.34)",
  },
  neon: {
    name: "Неон",
    bg: "linear-gradient(160deg, #0A0A1F 0%, #3D1E63 50%, #FF3D8A 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,.10) 0%, rgba(0,0,0,.55) 100%)",
    accent: "#FF7EC8",
    accentSoft: "rgba(255,126,200,.22)",
    timeShadow: "0 4px 60px rgba(255,61,138,.40)",
    bellGrad: "linear-gradient(135deg, #FF7EC8 0%, #C53578 60%, #5C1A4A 100%)",
    pillBg: "rgba(255,61,138,.20)",
    pillBorder: "rgba(255,126,200,.40)",
  },
  abstract: {
    name: "Абстракт",
    bg: "linear-gradient(160deg, #1E1E1E 0%, #2A2A2A 100%)",
    scrim: "radial-gradient(120% 80% at 50% 70%, rgba(0,0,0,0) 0%, rgba(0,0,0,.30) 100%)",
    accent: "#FFFFFF",
    accentSoft: "rgba(255,255,255,.12)",
    timeShadow: "0 4px 60px rgba(255,255,255,.10)",
    bellGrad: "linear-gradient(135deg, #FFFFFF 0%, #BFBFBF 60%, #6F6F6F 100%)",
    pillBg: "rgba(255,255,255,.10)",
    pillBorder: "rgba(255,255,255,.22)",
  },
};

/* ───── Firing screen, тематический. Статичный (без анимаций, без
   интерактива) — это чисто визуальное превью того, как firing-сцена
   выглядит в выбранной теме. */
function FiringTheme({ theme = "dawn" }) {
  const t = FIRING_THEMES[theme] || FIRING_THEMES.dawn;

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* Full-bleed theme background */}
      <div style={{ position: "absolute", inset: 0, background: t.bg }} aria-hidden/>
      {/* Scrim — затемняющий vignette + локальный glow в нижней трети */}
      <div style={{ position: "absolute", inset: 0, background: t.scrim, pointerEvents: "none" }} aria-hidden/>
      <div style={{
        position: "absolute", left: "50%", bottom: "-160px",
        transform: "translateX(-50%)",
        width: 460, height: 460, borderRadius: "50%",
        background: `radial-gradient(circle, ${t.accentSoft} 0%, transparent 65%)`,
        filter: "blur(24px)",
        pointerEvents: "none",
      }} aria-hidden/>

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* HEADER — дата + balance pill, окрашен в акцент темы. */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span className="sp-caps" style={{ color: "rgba(255,255,255,.55)" }}>Пт · 27 апр</span>
          <div className="dawn-bal" style={{
            color: t.accent,
            background: t.pillBg,
            borderColor: t.pillBorder,
          }}>
            <IconCoin size={12} />
            <span className="dawn-bal__label" style={{ color: t.accent, opacity: .85 }}>Баланс</span>
            <span className="dawn-bal__value" style={{ color: t.accent }}>840 ₽</span>
          </div>
        </div>

        {/* CENTER — bell ring, alarm name, large time, eyebrow.
            Размер и пропорции согласованы с FiringDawnV3, чтобы тема
            ощущалась как смена обоев, а не редизайн. */}
        <div style={{
          flex: 1, display: "flex", flexDirection: "column",
          justifyContent: "center", alignItems: "center",
          padding: "0 24px 16px", textAlign: "center", gap: 12,
        }}>
          {/* Bell icon — square, с легким ring'ом в цвет темы. */}
          <div style={{
            width: 72, height: 72, borderRadius: 22,
            background: t.bellGrad,
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: `0 0 0 6px ${t.accentSoft}, 0 12px 36px rgba(0,0,0,.35)`,
            marginBottom: 4,
          }}>
            <IconBell size={32} style={{ color: "rgba(0,0,0,.7)", strokeWidth: 2 }}/>
          </div>

          {/* Alarm name */}
          <div style={{
            font: "var(--sp-t-h3)",
            color: "rgba(255,255,255,.92)",
            letterSpacing: "-.01em",
          }}>
            Будни · 07:00
          </div>

          {/* Time — huge, mono, tabular-nums */}
          <div style={{
            font: "var(--sp-t-clock-xl)",
            color: "#FFF",
            letterSpacing: "-.05em",
            fontVariantNumeric: "tabular-nums",
            textShadow: t.timeShadow,
            marginTop: 4,
          }}>
            07:00
          </div>

          <div className="sp-caps" style={{
            color: t.accent, opacity: .85,
            letterSpacing: ".18em",
            marginTop: 4,
          }}>
            пора вставать
          </div>
        </div>

        {/* CTA — Spat' eshche + Я встал. Layout идентичен FiringDawnV3. */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 10 }}>
          <button className="dawn-snooze dawn-snooze--warn" type="button">
            <div className="dawn-snooze__caps">
              <IconClock size={14}/>
              Спать ещё 5 мин
            </div>
            <div className="dawn-snooze__price">
              −50<span className="dawn-snooze__cur">₽</span>
            </div>
            <div className="dawn-snooze__hint">следующее откладывание: 100 ₽</div>
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
              font: "600 16px/20px var(--sp-font-body)",
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

Object.assign(window, { FiringTheme, FIRING_THEMES });
