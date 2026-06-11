// SnoozePay · Woke Morning — позитивный экран после нажатия
// «Я встал — выключить» на сработавшем будильнике.
//
// Визуальный язык:
//   • тёмная заливка снизу → мятно-зелёный/бирюзовый туман сверху
//     (между «Лесом» и «Океаном» — спокойнее, светлее),
//   • subtle radial-glow зелёного под центральной иконкой,
//   • тонкая «линия горизонта» сквозь весь экран,
//   • большая ✓-иконка в money-градиенте с мягким сиянием,
//   • caps-eyebrow → крупный h1 → приглушённый subtitle,
//   • outline-кнопка «Закрыть» внизу с зелёной рамкой.
//
// Контент по двум сценариям:
//   snoozes === 0 → «Встал с первого раза» / «Баланс в полной сохранности.»
//   snoozes >  0 → «Удержались после N откладываний» / «Сегодня списано N ₽.»
//
// Анимация появления — fade + slide-up, длительностью 600 мс,
// со stagger 80 мс между элементами центральной композиции.

function WokeMorning({ snoozes = 0, charged = 0 } = {}) {
  const calm = snoozes === 0;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#060F0E" }}>
      {/* === ATMOSPHERE ============================================ */}

      {/* Base sky: мятный туман сверху, плавно темнеет вниз. */}
      <div aria-hidden style={{
        position: "absolute", inset: 0,
        background:
          "linear-gradient(180deg, #244E45 0%, #16332E 30%, #0B1C1A 60%, #07110F 100%)"
      }} />

      {/* Top mint mist — нечёткое пятно туманного утра. */}
      <div aria-hidden style={{
        position: "absolute", top: -160, left: "50%", transform: "translateX(-50%)",
        width: 560, height: 560, borderRadius: "50%",
        background:
          "radial-gradient(circle, rgba(158,230,204,.32) 0%, rgba(158,230,204,.10) 38%, transparent 68%)",
        filter: "blur(40px)", pointerEvents: "none"
      }} />

      {/* Horizon hairline — еле заметная линия чтобы дать сцене глубину. */}
      <div aria-hidden style={{
        position: "absolute", left: 0, right: 0, top: "44%", height: 1,
        background:
          "linear-gradient(90deg, transparent, rgba(158,230,204,.10) 50%, transparent)"
      }} />

      {/* Bottom green glow — тёплое сияние под нижним краем экрана. */}
      <div aria-hidden style={{
        position: "absolute", bottom: -160, left: "50%", transform: "translateX(-50%)",
        width: 520, height: 520, borderRadius: "50%",
        background:
          "radial-gradient(circle, rgba(46,219,159,.28) 0%, rgba(46,219,159,.06) 45%, transparent 72%)",
        filter: "blur(50px)", pointerEvents: "none"
      }} />

      {/* === STATUS BAR =========================================== */}
      <SPStatusBar time="7:00" tone="light" />

      {/* === CONTENT ============================================== */}
      <div style={{
        position: "absolute", inset: 0,
        padding: "54px 24px 32px",
        display: "flex", flexDirection: "column"
      }}>
        <div style={{
          flex: 1,
          display: "flex", flexDirection: "column",
          justifyContent: "center", alignItems: "center",
          textAlign: "center"
        }}>
          {/* ✓ icon — money gradient, soft outer glow. */}
          <div className="wm-step wm-step-1" style={{
            position: "relative",
            width: 84, height: 84, borderRadius: 20,
            background: "var(--sp-grad-money)",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow:
              "0 16px 48px rgba(46,219,159,.45), inset 0 0 0 1px rgba(255,255,255,.10)"
          }}>
            <IconCheck size={44} style={{ color: "#FFF", strokeWidth: 3 }} />
            <div aria-hidden style={{
              position: "absolute", inset: -30,
              borderRadius: 40, zIndex: -1,
              background:
                "radial-gradient(circle, rgba(46,219,159,.42) 0%, transparent 70%)",
              filter: "blur(22px)"
            }} />
          </div>

          {/* Eyebrow */}
          <div className="wm-step wm-step-2 sp-caps" style={{
            marginTop: 26,
            color: "#7CE0B9",
            fontSize: 12, fontWeight: 700,
            letterSpacing: ".16em"
          }}>
            Доброе утро
          </div>

          {/* Headline */}
          <div className="wm-step wm-step-3" style={{
            marginTop: 14,
            color: "#FFFFFF",
            fontFamily: "var(--sp-font-display, Manrope), Manrope, system-ui, sans-serif",
            fontWeight: 500,
            fontSize: 28, lineHeight: "34px",
            letterSpacing: "-.02em",
            maxWidth: 320,
            textWrap: "balance"
          }}>
            {calm
              ? "Встал с первого раза"
              : `Удержались после ${snoozes} откладываний`}
          </div>

          {/* Sub-headline */}
          <div className="wm-step wm-step-4" style={{
            marginTop: 14,
            color: "rgba(255,255,255,.62)",
            fontFamily: "var(--sp-font-text, Manrope), Manrope, system-ui, sans-serif",
            fontWeight: 400,
            fontSize: 15, lineHeight: "22px",
            maxWidth: 300,
            textWrap: "balance"
          }}>
            {calm
              ? "Баланс в полной сохранности. Так держать."
              : `Сегодня списано ${charged} ₽. Завтра попробуем не списать ничего.`}
          </div>
        </div>

        {/* Close — outline, green border. */}
        <button className="wm-step wm-step-5" type="button" style={{
          width: "100%", height: 56, borderRadius: 16,
          background: "transparent",
          border: "1px solid rgba(124,224,185,.45)",
          color: "#FFFFFF",
          fontFamily: "Manrope, system-ui, sans-serif",
          fontWeight: 600, fontSize: 16, letterSpacing: "-.01em",
          cursor: "pointer",
          transition: "background var(--sp-dur-quick, 140ms) ease, border-color var(--sp-dur-quick, 140ms) ease"
        }}
          onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(124,224,185,.08)"; e.currentTarget.style.borderColor = "rgba(124,224,185,.70)"; }}
          onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.borderColor = "rgba(124,224,185,.45)"; }}>
          Закрыть
        </button>
      </div>

      {/* Entry animation — slide-up + fade, stagger 80ms. */}
      <style>{`
        @keyframes wm-rise {
          from { opacity: 0; transform: translateY(18px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .wm-step {
          animation: wm-rise 600ms cubic-bezier(.2,.8,.2,1) both;
        }
        .wm-step-1 { animation-delay: 0ms;   }
        .wm-step-2 { animation-delay: 80ms;  }
        .wm-step-3 { animation-delay: 160ms; }
        .wm-step-4 { animation-delay: 240ms; }
        .wm-step-5 { animation-delay: 320ms; }
      `}</style>
    </div>
  );
}

Object.assign(window, { WokeMorning });
