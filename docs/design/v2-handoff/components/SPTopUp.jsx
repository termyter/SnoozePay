// SnoozePay — Top-up flow при активном будильнике (баланс кончился во время звонка)
// 3 варианта inline-пополнения + success + low-balance warning

const { useState: tuS } = React;

/* ============================================================
   ОБЩЕЕ: фон firing-screen в Dawn-стиле (выцветший, без энергии)
   Используется как фон для всех 3 вариантов
   ============================================================ */
function DawnDimBackground({ children }) {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden",
      background: "linear-gradient(180deg, #0E1320 0%, #2B1A0E 60%, #4A2410 100%)" }}>
      {/* Тусклый рассвет — Dawn без жизни, потому что баланс=0 */}
      <div style={{ position: "absolute", left: "50%", bottom: "-30%", transform: "translateX(-50%)",
        width: 520, height: 520, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.18) 0%, transparent 60%)", filter: "blur(40px)" }}/>
      {children}
    </div>
  );
}

/* ============================================================
   А · INLINE SHEET — тёплый Dawn, цена и пауза вшиты в один блок
   ============================================================ */
function FiringTopUpInline() {
  const [secLeft, setSecLeft] = tuS(54);
  return (
    <DawnDimBackground>
      <SPStatusBar time="7:14" tone="light"/>

      {/* Тусклый firing-контекст сверху */}
      <div style={{ position: "absolute", top: 80, left: 0, right: 0, textAlign: "center", opacity: .55 }}>
        <div className="sp-caps" style={{ color: "rgba(255,255,255,.6)" }}>Будни · Понедельник</div>
        <div style={{ font: "200 96px/96px var(--sp-font-mono)", color: "rgba(255,255,255,.85)",
          letterSpacing: "-.04em", marginTop: 8, fontVariantNumeric: "tabular-nums" }}>07:14</div>
      </div>

      {/* Inline sheet снизу */}
      <div style={{ position: "absolute", left: 12, right: 12, bottom: 16,
        background: "var(--sp-bg-2)", borderRadius: 28, border: "1px solid var(--sp-white-08)",
        padding: 24, backdropFilter: "blur(20px)" }}>

        {/* Pause-индикатор */}
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
          <div style={{ width: 8, height: 8, borderRadius: 4, background: "var(--sp-warn-400)",
            boxShadow: "0 0 12px var(--sp-warn-400)" }}/>
          <span className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Будильник на паузе</span>
          <span className="sp-meta" style={{ color: "var(--sp-fg-3)", marginLeft: "auto", fontFamily: "var(--sp-font-mono)" }}>
            00:{String(secLeft).padStart(2,"0")}
          </span>
        </div>

        <div style={{ font: "var(--sp-t-h2)", color: "#FFF", letterSpacing: "-.01em" }}>
          Баланс пуст
        </div>
        <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 6 }}>
          Чтобы поспать ещё раз, пополните баланс. Без него — только встать.
        </div>

        {/* Цена откладывания + сумма пополнения = одно и то же */}
        <div style={{ marginTop: 20, display: "flex", justifyContent: "space-between", alignItems: "baseline",
          padding: "16px 0", borderTop: "1px solid var(--sp-white-08)", borderBottom: "1px solid var(--sp-white-08)" }}>
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Следующее откладывание</div>
            <div style={{ font: "var(--sp-t-h4)", color: "#FFF", marginTop: 4 }}>9 минут сна</div>
          </div>
          <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-warn-400)" }}>{fmtRub(200)}</div>
        </div>

        {/* Apple Pay one-tap */}
        <button style={{
          marginTop: 16, width: "100%", padding: "16px 20px",
          borderRadius: 16, border: 0, cursor: "pointer",
          background: "#000", color: "#FFF",
          display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
          font: "var(--sp-t-button-lg)",
          boxShadow: "0 8px 24px rgba(0,0,0,.4)",
        }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <path d="M17.05 12.04c-.03-2.95 2.41-4.37 2.52-4.44-1.37-2.01-3.51-2.29-4.27-2.32-1.82-.18-3.55 1.07-4.48 1.07-.94 0-2.36-1.04-3.88-1.01-2 .03-3.84 1.16-4.86 2.95-2.07 3.59-.53 8.91 1.49 11.83.99 1.43 2.16 3.03 3.69 2.97 1.48-.06 2.04-.96 3.83-.96 1.78 0 2.29.96 3.85.93 1.59-.03 2.6-1.45 3.57-2.89 1.13-1.66 1.59-3.27 1.62-3.35-.04-.02-3.11-1.19-3.14-4.78zM14.13 4.27c.81-.99 1.36-2.36 1.21-3.72-1.17.05-2.59.78-3.43 1.76-.75.87-1.41 2.27-1.24 3.6 1.31.1 2.65-.66 3.46-1.64z"/>
          </svg>
          Доплатить 200 ₽
        </button>

        <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
          <SPButton variant="quiet" size="md" full>Пополнить на 1000 ₽</SPButton>
        </div>

        {/* Альтернатива */}
        <button style={{ marginTop: 12, width: "100%", border: 0, background: "transparent", padding: "8px 0",
          font: "var(--sp-t-button-md)", color: "var(--sp-fg-3)", cursor: "pointer" }}>
          Встать без откладываний
        </button>
      </div>
    </DawnDimBackground>
  );
}

/* ============================================================
   B · BOTTOM SHEET С ПРЕСЕТАМИ — выбираем сумму
   ============================================================ */
function FiringTopUpPresets() {
  const [sel, setSel] = tuS(200);
  const presets = [
    { v: 200,  l: "+1 откладывание",  hint: "ровно на сейчас" },
    { v: 500,  l: "+несколько",hint: "на пару дней" },
    { v: 1000, l: "+неделя",   hint: "забыть про баланс" },
  ];
  return (
    <DawnDimBackground>
      <SPStatusBar time="7:14" tone="light"/>

      {/* Тусклый firing-контекст */}
      <div style={{ position: "absolute", top: 80, left: 0, right: 0, textAlign: "center", opacity: .5 }}>
        <div className="sp-caps" style={{ color: "rgba(255,255,255,.6)" }}>Будни · Понедельник</div>
        <div style={{ font: "200 96px/96px var(--sp-font-mono)", color: "rgba(255,255,255,.85)",
          letterSpacing: "-.04em", marginTop: 8, fontVariantNumeric: "tabular-nums" }}>07:14</div>
      </div>

      {/* затемнение под шторкой */}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 540,
        background: "linear-gradient(180deg, transparent 0%, rgba(6,9,18,.6) 30%, var(--sp-bg-1) 100%)" }}/>

      {/* Bottom sheet */}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0,
        background: "var(--sp-bg-1)", borderTopLeftRadius: 28, borderTopRightRadius: 28,
        padding: "16px 16px 28px",
        boxShadow: "0 -16px 48px rgba(0,0,0,.5)" }}>

        {/* drag handle */}
        <div style={{ width: 36, height: 4, borderRadius: 2, background: "var(--sp-white-12)",
          margin: "0 auto 16px" }}/>

        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
          <div style={{ width: 8, height: 8, borderRadius: 4, background: "var(--sp-warn-400)" }}/>
          <span className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Будильник на паузе · 00:54</span>
        </div>
        <div style={{ font: "var(--sp-t-h2)", color: "#FFF", letterSpacing: "-.01em" }}>Пополнить баланс</div>
        <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 4 }}>
          Минимум — 200 ₽ на следующее откладывание. Можно больше, чтобы не возвращаться сюда.
        </div>

        {/* Пресеты */}
        <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 20 }}>
          {presets.map(p => {
            const on = sel === p.v;
            return (
              <button key={p.v} onClick={()=>setSel(p.v)} style={{
                width: "100%", padding: "16px 20px", borderRadius: 16, cursor: "pointer",
                border: on ? "1px solid var(--sp-warn-400)" : "1px solid var(--sp-white-08)",
                background: on ? "rgba(245,158,11,.08)" : "var(--sp-white-04)",
                display: "flex", alignItems: "center", justifyContent: "space-between",
                font: "var(--sp-t-button-md)", color: "#FFF", textAlign: "left",
              }}>
                <div>
                  <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{p.l}</div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>{p.hint}</div>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ font: "var(--sp-t-money-md)",
                    color: on ? "var(--sp-warn-400)" : "#FFF" }}>
                    {fmtRub(p.v)}
                  </span>
                  {on && (
                    <div style={{ width: 22, height: 22, borderRadius: 11,
                      background: "var(--sp-grad-warn)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <IconCheck size={14} style={{ color: "var(--sp-fg-on-warn)" }}/>
                    </div>
                  )}
                </div>
              </button>
            );
          })}
        </div>

        {/* Apple Pay */}
        <button style={{
          marginTop: 16, width: "100%", padding: "16px 20px",
          borderRadius: 16, border: 0, cursor: "pointer",
          background: "#000", color: "#FFF",
          display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
          font: "var(--sp-t-button-lg)",
        }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <path d="M17.05 12.04c-.03-2.95 2.41-4.37 2.52-4.44-1.37-2.01-3.51-2.29-4.27-2.32-1.82-.18-3.55 1.07-4.48 1.07-.94 0-2.36-1.04-3.88-1.01-2 .03-3.84 1.16-4.86 2.95-2.07 3.59-.53 8.91 1.49 11.83.99 1.43 2.16 3.03 3.69 2.97 1.48-.06 2.04-.96 3.83-.96 1.78 0 2.29.96 3.85.93 1.59-.03 2.6-1.45 3.57-2.89 1.13-1.66 1.59-3.27 1.62-3.35-.04-.02-3.11-1.19-3.14-4.78zM14.13 4.27c.81-.99 1.36-2.36 1.21-3.72-1.17.05-2.59.78-3.43 1.76-.75.87-1.41 2.27-1.24 3.6 1.31.1 2.65-.66 3.46-1.64z"/>
          </svg>
          Pay {sel} ₽
        </button>

        <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center", marginTop: 10 }}>
          Apple Pay · 3D Secure не нужен
        </div>
      </div>
    </DawnDimBackground>
  );
}

/* ============================================================
   C · ONE-TAP FULL-SCREEN — максимально быстро, всё фокус на одной кнопке
   ============================================================ */
function FiringTopUpOneTap() {
  return (
    <DawnDimBackground>
      <SPStatusBar time="7:14" tone="light"/>

      <div style={{ position: "absolute", inset: 0, padding: "54px 16px 32px",
        display: "flex", flexDirection: "column" }}>

        {/* Top — pause indicator */}
        <div style={{ paddingTop: 16, display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{ width: 10, height: 10, borderRadius: 5, background: "var(--sp-warn-400)",
            boxShadow: "0 0 16px var(--sp-warn-400)" }}/>
          <span className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Будильник на паузе</span>
          <span className="sp-meta" style={{ marginLeft: "auto", color: "var(--sp-fg-3)",
            fontFamily: "var(--sp-font-mono)" }}>00:54</span>
        </div>

        {/* Огромный hero — цена */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "flex-start", marginTop: -20 }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Баланс</div>
          <div style={{ display: "flex", alignItems: "baseline", marginTop: 4, gap: 12 }}>
            <span style={{ font: "var(--sp-t-money-xl)", color: "var(--sp-fg-3)",
              fontVariantNumeric: "tabular-nums", textDecoration: "line-through" }}>0</span>
            <span style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-3)" }}>₽</span>
          </div>

          <div style={{ marginTop: 32 }}>
            <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Чтобы поспать ещё раз</div>
            <div style={{ display: "flex", alignItems: "baseline", marginTop: 8, gap: 10 }}>
              <span style={{ font: "180px/180px var(--sp-font-mono)", color: "#FFF",
                letterSpacing: "-.06em", fontVariantNumeric: "tabular-nums" }}>200</span>
              <span style={{ font: "var(--sp-t-money-xl)", color: "var(--sp-warn-400)" }}>₽</span>
            </div>
            <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 12, maxWidth: 320 }}>
              Минимум — ровно на следующее откладывание. Дальше будильник продолжит звонить.
            </div>
          </div>
        </div>

        {/* Bottom — одна гигантская кнопка */}
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <button style={{
            width: "100%", padding: "20px 20px",
            borderRadius: 20, border: 0, cursor: "pointer",
            background: "#000", color: "#FFF",
            display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
            font: "var(--sp-t-h3)",
            boxShadow: "0 12px 32px rgba(0,0,0,.5)",
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.05 12.04c-.03-2.95 2.41-4.37 2.52-4.44-1.37-2.01-3.51-2.29-4.27-2.32-1.82-.18-3.55 1.07-4.48 1.07-.94 0-2.36-1.04-3.88-1.01-2 .03-3.84 1.16-4.86 2.95-2.07 3.59-.53 8.91 1.49 11.83.99 1.43 2.16 3.03 3.69 2.97 1.48-.06 2.04-.96 3.83-.96 1.78 0 2.29.96 3.85.93 1.59-.03 2.6-1.45 3.57-2.89 1.13-1.66 1.59-3.27 1.62-3.35-.04-.02-3.11-1.19-3.14-4.78zM14.13 4.27c.81-.99 1.36-2.36 1.21-3.72-1.17.05-2.59.78-3.43 1.76-.75.87-1.41 2.27-1.24 3.6 1.31.1 2.65-.66 3.46-1.64z"/>
            </svg>
            Pay
          </button>
          <SPButton variant="quiet" size="md" full>Другая сумма</SPButton>
          <button style={{ width: "100%", border: 0, background: "transparent", padding: "10px 0",
            font: "var(--sp-t-button-md)", color: "var(--sp-fg-3)", cursor: "pointer" }}>
            Встать без откладываний →
          </button>
        </div>
      </div>
    </DawnDimBackground>
  );
}

/* ============================================================
   SUCCESS — после оплаты, возврат к firing с обновлённым балансом
   ============================================================ */
function FiringTopUpSuccess() {
  return (
    <DawnDimBackground>
      <SPStatusBar time="7:14" tone="light"/>

      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column",
        justifyContent: "center", alignItems: "center", padding: 24 }}>

        {/* Animated checkmark */}
        <div style={{
          width: 96, height: 96, borderRadius: 48,
          background: "var(--sp-grad-money)",
          display: "flex", alignItems: "center", justifyContent: "center",
          boxShadow: "0 16px 48px rgba(43,194,140,.40)",
        }}>
          <IconCheck size={48} style={{ color: "var(--sp-fg-on-money)" }}/>
        </div>

        <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 24, letterSpacing: "-.02em", textAlign: "center" }}>
          Баланс пополнен
        </div>
        <div style={{ font: "var(--sp-t-money-xl)", color: "var(--sp-money-400)",
          marginTop: 8, fontVariantNumeric: "tabular-nums" }}>
          +200 <span style={{ fontSize: 32, color: "var(--sp-fg-3)" }}>₽</span>
        </div>
        <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 16, textAlign: "center", maxWidth: 280 }}>
          Возвращаем к будильнику через 2 секунды
        </div>
      </div>

      {/* Bottom — pause continuing */}
      <div style={{ position: "absolute", left: 24, right: 24, bottom: 32, textAlign: "center" }}>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)" }}>
          Apple Pay · списано 200 ₽
        </div>
      </div>
    </DawnDimBackground>
  );
}

/* ============================================================
   LOW BALANCE WARNING на главном (Alarms list)
   Когда баланс < 100 ₽ — баннер сверху
   ============================================================ */
function AlarmsListLowBalance() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        {/* Top nav */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>SnoozePay</div>
            <div style={{ font: "var(--sp-t-h1)", color: "#FFF", letterSpacing: "-.02em", marginTop: 2 }}>Будильники</div>
          </div>
          <button style={{ width: 44, height: 44, borderRadius: 22, border: 0, background: "var(--sp-white-08)",
            color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconPlus size={22}/>
          </button>
        </div>

        {/* LOW BALANCE BANNER — теплый акцент, не пугающий */}
        <div style={{ padding: "16px 16px 0" }}>
          <div style={{ position: "relative", borderRadius: 20, overflow: "hidden",
            background: "linear-gradient(135deg, #2B1A0E 0%, #4A2410 60%, #6B3517 100%)",
            border: "1px solid rgba(245,158,11,.30)" }}>
            <div style={{ position: "absolute", right: -40, top: -40, width: 180, height: 180, borderRadius: "50%",
              background: "radial-gradient(circle, rgba(255,184,77,.30) 0%, transparent 60%)", filter: "blur(20px)" }}/>
            <div style={{ position: "relative", padding: 20 }}>
              <div style={{ display: "flex", alignItems: "flex-start", gap: 14 }}>
                <div style={{ width: 44, height: 44, borderRadius: 14, background: "var(--sp-grad-warn)",
                  display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
                  boxShadow: "0 8px 24px rgba(245,158,11,.40)" }}>
                  <IconCoin size={22} style={{ color: "var(--sp-fg-on-warn)" }}/>
                </div>
                <div style={{ flex: 1 }}>
                  <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Баланс почти пуст</div>
                  <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginTop: 4 }}>
                    <span style={{ font: "var(--sp-t-money-md)", color: "#FFF" }}>{fmtRub(50)}</span>
                    <span className="sp-meta" style={{ color: "rgba(255,255,255,.7)" }}>· хватит на 1 откладывание</span>
                  </div>
                  <div className="sp-body" style={{ color: "rgba(255,255,255,.85)", marginTop: 8 }}>
                    Утром при пустом балансе будильник можно будет только выключить.
                  </div>
                  <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
                    <button style={{
                      flex: 1, padding: "12px 20px", borderRadius: 12, border: 0, cursor: "pointer",
                      background: "var(--sp-grad-warn)", color: "var(--sp-fg-on-warn)",
                      font: "var(--sp-t-button-md)",
                    }}>Пополнить 500 ₽</button>
                    <button style={{
                      padding: "12px 12px", borderRadius: 12, border: "1px solid rgba(255,255,255,.20)", cursor: "pointer",
                      background: "transparent", color: "#FFF", font: "var(--sp-t-button-md)",
                    }}>Другая сумма</button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Список будильников (укороченный) */}
        <div style={{ padding: "20px 16px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 10 }}>
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <div>
                <div style={{ font: "var(--sp-t-clock-md)", color: "#FFF", fontVariantNumeric: "tabular-nums",
                  letterSpacing: "-.03em" }}>07:00</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>Будни · Пн–Пт · 50 ₽ за откладывание</div>
              </div>
              <SPSwitch checked={true} onChange={()=>{}}/>
            </div>
          </SPCard>
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <div>
                <div style={{ font: "var(--sp-t-clock-md)", color: "var(--sp-fg-3)", fontVariantNumeric: "tabular-nums",
                  letterSpacing: "-.03em" }}>09:30</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>Выходные · Сб–Вс</div>
              </div>
              <SPSwitch checked={false} onChange={()=>{}}/>
            </div>
          </SPCard>
        </div>

        {/* tab bar */}
        <SPTabBar active="alarms" onTab={()=>{}}/>
      </div>
    </div>
  );
}

Object.assign(window, {
  FiringTopUpInline, FiringTopUpPresets, FiringTopUpOneTap,
  FiringTopUpSuccess, AlarmsListLowBalance,
});
