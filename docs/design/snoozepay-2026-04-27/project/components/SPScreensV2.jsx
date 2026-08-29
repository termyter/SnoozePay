// SnoozePay v2 — улучшенные экраны.
// Цель: атмосфера + ясная иерархия + продуктовый якорь (цена откладывания).
// 3 варианта firing-screen + остальные ключевые.

const { useState: uS, useEffect: uE, useRef: uR } = React;

/* ───── Phone shell ───── */
function Phone({ children, theme = "dark", label }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16 }}>
      <div className="phone">
        <div className="phone__notch" />
        <div data-theme={theme} className="phone__screen" style={{ background: "var(--sp-bg-0)" }}>
          {children}
        </div>
        <div className="phone__home" />
      </div>
      {label && <div style={{ font: "var(--sp-t-caps)", color: "var(--sp-fg-3)" }}>{label}</div>}
    </div>
  );
}

/* ───── Animated price pulse — общий ───── */
function PulseDot({ color = "rgba(255,184,77,.6)" }) {
  return (
    <span style={{
      display: "inline-block", width: 8, height: 8, borderRadius: "50%",
      background: color, boxShadow: `0 0 0 0 ${color}`,
      animation: "sp-pulse 1.6s var(--sp-ease-out) infinite",
    }} />
  );
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
        background: "radial-gradient(140% 70% at 50% 100%, rgba(245,158,11,.22) 0%, rgba(244,82,63,.10) 30%, transparent 60%), linear-gradient(180deg, #0A0E1A 0%, #0E1320 60%, #1A1410 100%)",
      }} />
      {/* «солнце» */}
      <div style={{
        position: "absolute", left: "50%", bottom: "-120px", transform: "translateX(-50%)",
        width: 320, height: 320, borderRadius: "50%",
        background: progressive
          ? "radial-gradient(circle, rgba(244,82,63,.35) 0%, rgba(244,82,63,.08) 40%, transparent 70%)"
          : "radial-gradient(circle, rgba(255,184,77,.40) 0%, rgba(245,158,11,.10) 40%, transparent 70%)",
        filter: "blur(20px)",
      }} />

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* верх: дата + баланс */}
        <div style={{ padding: "16px 24px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.55)" }}>Пт · 27 апр</div>
          <SPPill tone={progressive ? "pain" : "money"} icon={<IconCoin size={12}/>}>
            {fmtRub(progressive ? 540 : 840)}
          </SPPill>
        </div>

        {/* центр: время */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 24px" }}>
          <div style={{
            font: "var(--sp-t-clock-xl)", color: "#FFF",
            letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums",
            textShadow: "0 4px 60px rgba(255,184,77,.25)",
          }}>
            <span>07</span>
            <span style={{ opacity: .35, padding: "0 4px" }}>:</span>
            <span>00</span>
          </div>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)", marginTop: 8 }}>Подъём</div>
          {progressive && (
            <div style={{ marginTop: 16, display: "flex", alignItems: "center", gap: 8 }}>
              <PulseDot color="rgba(244,82,63,.8)" />
              <span className="sp-caps" style={{ color: "var(--sp-pain-300)", letterSpacing: ".18em" }}>Прогрессив · 4-е откладывание</span>
            </div>
          )}
        </div>

        {/* низ: snooze + я встал */}
        <div style={{ padding: "0 20px 32px", display: "flex", flexDirection: "column", gap: 12 }}>
          <SPSnoozePrice
            price={price}
            tone={tone}
            minutes={5}
            hint={next ? `Следующее откладывание: ${fmtRub(next)}` : "Цена фиксированная"}
          />
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   FIRING — Вариант B: «Money on the line» (продуктовый, цифра-первая)
   Цена СВЕРХУ как hero, время — поддержка.
   ============================================================ */
function FiringMoneyFirst({ progressive }) {
  const price = progressive ? 200 : 50;
  const next  = progressive ? price * 2 : null;
  const tone = progressive ? "pain" : "warn";

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: progressive ? "#1A0A0A" : "#0E1320" }}>
      {/* Тёплое свечение цены сверху */}
      <div style={{
        position: "absolute", top: -80, left: "50%", transform: "translateX(-50%)",
        width: 480, height: 320, borderRadius: "50%",
        background: progressive
          ? "radial-gradient(circle, rgba(244,82,63,.45) 0%, transparent 60%)"
          : "radial-gradient(circle, rgba(255,184,77,.40) 0%, transparent 60%)",
        filter: "blur(40px)",
      }} />

      <SPStatusBar time="7:00" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* hero: цена доминирует */}
        <div style={{ padding: "32px 24px 0", textAlign: "center" }}>
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
            letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums",
          }}>
            {price}<span style={{ fontSize: 56, opacity: .85 }}>&nbsp;₽</span>
          </div>
          {next && (
            <div className="sp-meta" style={{ color: "rgba(255,255,255,.55)", marginTop: 8 }}>
              следующее откладывание: <span style={{ fontFamily: "var(--sp-font-mono)", color: "rgba(255,255,255,.85)" }}>{fmtRub(next)}</span>
            </div>
          )}
        </div>

        {/* time + balance */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "0 24px" }}>
          <div style={{
            font: "200 64px/64px var(--sp-font-mono)", color: "rgba(255,255,255,.85)",
            letterSpacing: "-.03em", fontVariantNumeric: "tabular-nums",
          }}>
            7:00
          </div>
          <div style={{ marginTop: 24, display: "flex", gap: 8 }}>
            <SPPill icon={<IconCoin size={12}/>} tone="money">Баланс {fmtRub(progressive ? 540 : 840)}</SPPill>
          </div>
        </div>

        {/* CTA */}
        <div style={{ padding: "0 20px 32px", display: "flex", flexDirection: "column", gap: 12 }}>
          <button className={`sp-btn sp-btn--lg sp-btn--full sp-btn--${tone === "pain" ? "pain" : "warn"}`}>
            <IconClock size={18}/>
            <span className="sp-btn__label">Откупиться · спать ещё 5 мин</span>
          </button>
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </div>
  );
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
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 24px" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.45)" }}>Будильник</div>
          <div style={{ font: "100 128px/128px var(--sp-font-mono)", color: "#FFF", marginTop: 12, letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>
            7:00
          </div>
          <div style={{ marginTop: 40, height: 1, width: 60, background: "rgba(255,255,255,.2)" }} />
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.45)", marginTop: 24 }}>Цена откладывания</div>
          <div style={{
            font: "700 56px/60px var(--sp-font-mono)",
            color: progressive ? "var(--sp-pain-400)" : "var(--sp-warn-400)",
            marginTop: 4, fontVariantNumeric: "tabular-nums",
          }}>
            {fmtRub(price)}
          </div>
        </div>

        <div style={{ padding: "0 20px 32px", display: "flex", flexDirection: "column", gap: 8 }}>
          <button style={{
            height: 64, borderRadius: 32, border: 0, cursor: "pointer",
            background: "transparent", color: "rgba(255,255,255,.85)",
            font: "var(--sp-t-button)",
            border: "1.5px solid rgba(255,255,255,.2)",
          }}>
            Отложить · −{fmtRub(price)}
          </button>
          <button style={{
            height: 64, borderRadius: 32, border: 0, cursor: "pointer",
            background: "#FFF", color: "#000",
            font: "var(--sp-t-button)",
          }}>
            Я встал
          </button>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   FIRING — No balance (доработанный)
   ============================================================ */
function FiringNoBalanceV2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, #0E1320 0%, #160B0B 100%)", overflow: "hidden" }}>
      <SPStatusBar time="7:00" tone="light" />
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "16px 24px 0", display: "flex", justifyContent: "flex-end" }}>
          <SPPill tone="pain" icon={<IconCoin size={12}/>}>Баланс 0 ₽</SPPill>
        </div>

        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 24px", textAlign: "center" }}>
          <div style={{ font: "var(--sp-t-clock-xl)", color: "#FFF", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>7:00</div>
          <div style={{
            marginTop: 28, padding: "10px 18px",
            background: "rgba(244,82,63,.12)", borderRadius: 999,
            border: "1px solid rgba(244,82,63,.3)",
            display: "inline-flex", alignItems: "center", gap: 8,
          }}>
            <IconShield size={14} style={{ color: "var(--sp-pain-300)" }} />
            <span className="sp-caps" style={{ color: "var(--sp-pain-300)" }}>Баланса не осталось</span>
          </div>
          <div style={{ marginTop: 18, color: "rgba(255,255,255,.7)", maxWidth: 260, font: "var(--sp-t-body-lg)" }}>
            Откладывать больше не получится. Только встать.
          </div>
        </div>

        <div style={{ padding: "0 20px 32px", display: "flex", flexDirection: "column", gap: 10 }}>
          <SPSnoozePrice price={50} disabled minutes={5} hint="Недостаточно средств" />

          {/* Главное действие — пополнить через Apple Pay в один тап.
              Tone «money» — зелёный градиент, как на остальных money-CTA. */}
          <SPButton variant="money" size="lg" full
            icon={
              <svg width="18" height="22" viewBox="0 0 18 22" fill="none" aria-hidden>
                <path d="M14.6 11.7c0-2 1.6-3 1.7-3-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.7-3.1.7-.7 0-1.7-.7-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.3 1 8.4.7 1 1.6 2.1 2.7 2 1.1 0 1.5-.7 2.7-.7 1.3 0 1.6.7 2.7.7 1.1 0 1.9-1 2.5-2 .8-1.1 1.1-2.2 1.2-2.3 0 0-2.3-.9-2.3-3.5zM12.7 5.5c.6-.7 1-1.7.9-2.7-.9 0-1.9.6-2.5 1.3-.5.6-1 1.6-.9 2.6 1 .1 1.9-.5 2.5-1.2z" fill="currentColor"/>
              </svg>
            }
            suffix="500 ₽">
            Apple Pay
          </SPButton>

          {/* Вторичное действие — выключить будильник.
              Размер lg как у Apple Pay (это полноценный путь, не «отказ»),
              variant ghost — обведённая прозрачная, чтобы не конкурировать с money-CTA. */}
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   ALARMS LIST v2 — главный экран
   ============================================================ */
function AlarmsListV2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        {/* === STICKY HEADER: title + balance === */}
        <div style={{
          padding: "8px 20px 16px",
          background: "var(--sp-bg-0)",
          borderBottom: "1px solid var(--sp-white-06)",
          flexShrink: 0,
          position: "relative", zIndex: 2,
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Будильники</div>
            <button style={{
              width: 40, height: 40, borderRadius: 20, border: 0,
              background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
              display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
              boxShadow: "var(--sp-shadow-money)",
            }}>
              <IconPlus size={20} />
            </button>
          </div>

          {/* Balance pill — компактный sticky.
              Сумма + подпись «хватит на N» — в две строки внутри центрального блока,
              чтобы не наезжать на кнопку «Пополнить». */}
          <button style={{
            marginTop: 12, width: "100%", padding: "12px 14px",
            borderRadius: 14, border: "1px solid var(--sp-white-08)",
            background: "var(--sp-bg-2)", cursor: "pointer",
            display: "flex", alignItems: "center", gap: 12, textAlign: "left",
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: 10, background: "var(--sp-grad-money)",
              display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
            }}>
              <IconWallet size={18} style={{ color: "var(--sp-fg-on-money)" }}/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
                <span className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Баланс</span>
                <span style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>840 ₽</span>
              </div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>
                Хватит на ~16 откладываний
              </div>
            </div>
            <SPButton variant="money" size="sm">Пополнить</SPButton>
          </button>
        </div>

        {/* === SCROLL AREA === */}
        <div style={{ flex: 1, overflowY: "auto", padding: "16px 20px 20px", display: "flex", flexDirection: "column", gap: 12 }}>
          {/* Streak summary */}
          <div style={{
            padding: "14px 16px", borderRadius: 16,
            background: "linear-gradient(135deg, rgba(46,219,159,.12) 0%, rgba(46,219,159,.04) 100%)",
            border: "1px solid rgba(46,219,159,.18)",
            display: "flex", alignItems: "center", gap: 12,
          }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10, background: "var(--sp-grad-money)",
              display: "flex", alignItems: "center", justifyContent: "center",
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
                  7:00
                </div>
              </div>
              <SPSwitch checked={true} onChange={()=>{}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14, flexWrap: "wrap" }}>
              <SPPill tone="warn" icon={<IconCoin size={12}/>}>50 ₽</SPPill>
              <SPPill tone="pain" icon={<IconFlame size={12}/>}>×2</SPPill>
              <SPPill icon={<IconSound size={12}/>}>Soft Dawn</SPPill>
            </div>
          </SPCard>

          <SPCard tone="surface" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Выходные</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  9:30
                </div>
              </div>
              <SPSwitch checked={false} onChange={()=>{}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14 }}>
              <SPPill>20 ₽</SPPill>
              <SPPill>Birds</SPPill>
            </div>
          </SPCard>

          <SPCard tone="surface" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Спорт · Вт, Чт</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  6:15
                </div>
              </div>
              <SPSwitch checked={false} onChange={()=>{}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14 }}>
              <SPPill tone="warn">100 ₽</SPPill>
              <SPPill>Energy</SPPill>
            </div>
          </SPCard>
        </div>

        <SPTabBar active="alarms" />
      </div>
    </div>
  );
}

/* ============================================================
   WALLET v2
   ============================================================ */
/* Кошелёк — ИНФОРМАЦИОННЫЙ таб (#233): баланс, недельный чарт, превью истории.
   Грида пресетов и нижнего CTA здесь нет — выбор суммы переехал в Deposit
   bottom sheet (артборд 19), который открывает money-пилюля «Пополнить»
   в шапке. Строки «Способы оплаты» нет: экран не входит в MVP (#237/#521). */
function WalletV2() {
  const tx = [
    { title: "Поспать ещё",        when: "Сегодня · 07:09", amount: "−50 ₽",  debit: true,  icon: <IconFlame size={18}/> },
    { title: "Пополнение баланса", when: "Вчера · 21:32",   amount: "+500 ₽", debit: false, icon: <IconPlus size={18}/> },
    { title: "Бонус за друга",     when: "12 апр. · 09:00", amount: "+200 ₽", debit: false, icon: <IconCoin size={18}/> },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        {/* Page-title header: h1 + money-пилюля «Пополнить» + hairline —
            та же раскладка, что у AlarmsListV2, чтобы табы читались одинаково. */}
        <div style={{
          padding: "8px 20px 16px", background: "var(--sp-bg-0)",
          borderBottom: "1px solid var(--sp-white-06)", flexShrink: 0,
          display: "flex", justifyContent: "space-between", alignItems: "center",
        }}>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Кошелёк</div>
          <SPButton variant="money" size="sm" icon={<IconPlus size={16}/>}>Пополнить</SPButton>
        </div>

        <div style={{ padding: "16px 20px 20px", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 24 }}>
          <SPBalanceCard balance={840} delta={-160} hint="Хватит на ~17 откладываний при текущей цене" />

          <div>
            <div className="sp-caps" style={{ marginBottom: 10 }}>Последние 7 дней</div>
            <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 60 }}>
              {[40, 0, 80, 50, 0, 0, 30].map((v, i) => (
                <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                  <div style={{
                    width: "100%", height: v ? `${v}%` : 4,
                    borderRadius: 4, minHeight: 4,
                    background: v ? "var(--sp-grad-pain)" : "var(--sp-white-08)",
                    opacity: v ? 1 : .5,
                  }} />
                  <div className="sp-meta" style={{ color: "var(--sp-fg-4)", fontSize: 10 }}>
                    {["П","В","С","Ч","П","С","В"][i]}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Превью истории: 3 последние операции + ссылка в полный TxHistory. */}
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 10 }}>
              <div className="sp-caps">История операций</div>
              <span style={{ font: "var(--sp-t-button-sm)", color: "var(--sp-money-400)", cursor: "pointer" }}>Все операции →</span>
            </div>
            <SPCard padding={4} radius={16}>
              {tx.map((t, i) => (
                <SPRow
                  key={t.title}
                  divider={i < tx.length - 1}
                  leading={
                    <div style={{
                      width: 36, height: 36, borderRadius: 10,
                      background: t.debit ? "rgba(244,82,63,.14)" : "rgba(46,219,159,.14)",
                      color: t.debit ? "var(--sp-pain-400)" : "var(--sp-money-400)",
                      display: "flex", alignItems: "center", justifyContent: "center",
                    }}>{t.icon}</div>
                  }
                  title={t.title}
                  subtitle={t.when}
                  trailing={
                    <span style={{ font: "var(--sp-t-money-md)", color: t.debit ? "var(--sp-pain-400)" : "var(--sp-money-400)", fontVariantNumeric: "tabular-nums" }}>
                      {t.amount}
                    </span>
                  }
                />
              ))}
            </SPCard>
          </div>

          <div className="sp-meta" style={{ textAlign: "center", color: "var(--sp-fg-4)" }}>
            Покупка не возвращается · списывается только при откладывании
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   CREATE ALARM v2
   ============================================================ */
function CreateAlarmV2() {
  const [name, setName] = uS("");
  const [snoozeMin, setSnoozeMin] = uS(9);
  const [prog, setProg] = uS(true);
  const [price, setPrice] = uS(50);
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light" />
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>

        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconClose size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Новый будильник</div>
          <SPButton variant="money" size="sm">Готово</SPButton>
        </div>

        {/* Name input — iOS Reminders style */}
        <div style={{ padding: "12px 20px 0" }}>
          <input
            value={name}
            onChange={(e)=>setName(e.target.value)}
            placeholder="Название · напр. Будни"
            style={{
              width: "100%", border: 0, outline: "none", background: "transparent",
              color: "var(--sp-fg-1)", caretColor: "var(--sp-warn-400)",
              font: "var(--sp-t-h1)", letterSpacing: "-.02em",
              padding: "8px 0 12px",
              borderBottom: "1px solid var(--sp-white-08)",
            }}
          />
        </div>

        {/* Wheel-time picker */}
        <div style={{ padding: "20px 20px 0", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 6 }}>Подъём</div>
          <div style={{ display: "inline-flex", alignItems: "baseline", gap: 4 }}>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>07</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-4)", padding: "0 4px" }}>:</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>00</span>
          </div>
          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 12 }}>
            {["Пн","Вт","Ср","Чт","Пт","Сб","Вс"].map((d, i) => {
              const on = i < 5;
              return (
                <button key={d} style={{
                  width: 36, height: 36, borderRadius: 18, border: 0,
                  background: on ? "var(--sp-grad-money)" : "var(--sp-white-06)",
                  color: on ? "var(--sp-fg-on-money)" : "var(--sp-fg-3)",
                  font: "var(--sp-t-button-sm)",
                  cursor: "pointer",
                }}>{d}</button>
              );
            })}
          </div>

          {/* ПОВТОР — сегмент «Никогда / Еженедельно» + подсказка под чипами
              дней (#229). Живёт в обоих режимах формы, Create и Edit. */}
          <div style={{ marginTop: 16, textAlign: "left" }}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Повтор</div>
            <SPSegmented
              options={[{value:"never",label:"Никогда"},{value:"weekly",label:"Еженедельно"}]}
              value="weekly" onChange={()=>{}}
            />
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 8, textAlign: "center" }}>
              Будет повторяться каждую неделю по выбранным дням.
            </div>
          </div>
        </div>

        <div style={{ padding: "24px 20px 0", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflowY: "auto" }}>

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
              onChange={(e)=>setSnoozeMin(+e.target.value)}
              style={{
                width: "100%", appearance: "none", WebkitAppearance: "none",
                height: 6, borderRadius: 3,
                background: `linear-gradient(90deg, var(--sp-warn-500) 0%, var(--sp-warn-500) ${(snoozeMin-1)/14*100}%, rgba(255,255,255,.10) ${(snoozeMin-1)/14*100}%, rgba(255,255,255,.10) 100%)`,
                outline: "none", cursor: "pointer",
              }}
            />
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
              <span className="sp-meta" style={{ color: "var(--sp-fg-4)" }}>1 мин</span>
              <span className="sp-meta" style={{ color: "var(--sp-fg-4)" }}>15 мин</span>
            </div>
          </SPCard>

          <SPCard padding={4} radius={20}>
            <SPRow
              leading={<IconSound size={20} style={{ color: "var(--sp-fg-3)" }}/>}
              title="Звук"
              trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}
            />
            <SPRow
              leading={<div style={{ width: 28, height: 28, borderRadius: 8, overflow: "hidden",
                background: "linear-gradient(135deg, #2B1A0E 0%, #6B3517 50%, #C46A1A 100%)" }}/>}
              title="Тема"
              trailing={<><span className="sp-meta">Рассвет</span><IconChevR size={16}/></>}
            />
            <SPRow
              divider={false}
              leading={<IconBell size={20} style={{ color: "var(--sp-fg-3)" }}/>}
              title="Вибрация"
              trailing={<SPSwitch checked={true} onChange={()=>{}}/>}
            />
          </SPCard>

          {/* Snooze price slider */}
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 16 }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Цена откладывания</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Сколько спишется при «отложить»</div>
              </div>
            </div>
            {/* Сумма — свободный ввод (numberPad), пресеты только ускоряют.
                Минимум 1 ₽, максимума нет (#231). */}
            <div style={{ display: "flex", alignItems: "baseline", gap: 6, marginBottom: 12 }}>
              <span style={{ font: "700 32px/36px var(--sp-font-mono)", color: "var(--sp-warn-400)", fontVariantNumeric: "tabular-nums" }}>{price}</span>
              <span style={{ font: "700 32px/36px var(--sp-font-mono)", color: "var(--sp-warn-400)" }}>₽</span>
            </div>
            <div style={{ display: "flex", gap: 6 }}>
              {[20, 50, 100, 200, 500].map(v => (
                <button key={v} onClick={()=>setPrice(v)} style={{
                  flex: 1, height: 40, borderRadius: 12, border: 0, cursor: "pointer",
                  background: price === v ? "var(--sp-grad-warn)" : "var(--sp-white-06)",
                  color: price === v ? "var(--sp-fg-on-warn)" : "var(--sp-fg-2)",
                  font: "var(--sp-t-button-sm)",
                  fontFamily: "var(--sp-font-mono)",
                }}>
                  {v}
                </button>
              ))}
            </div>
          </SPCard>

          <SPCard padding={20} radius={20}
            style={prog ? { background: "linear-gradient(135deg, rgba(244,82,63,.10), rgba(244,82,63,.02))", border: "1px solid rgba(244,82,63,.25)" } : {}}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
              <div style={{ flex: 1 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <IconFlame size={18} style={{ color: prog ? "var(--sp-pain-400)" : "var(--sp-fg-3)" }}/>
                  <div className="sp-h4">Прогрессивный режим</div>
                </div>
                <div className="sp-meta" style={{ marginTop: 6, color: "var(--sp-fg-3)" }}>
                  Каждое откладывание — в 2 раза дороже.
                </div>
                {prog && (
                  <div style={{ marginTop: 12, display: "flex", gap: 8, alignItems: "center", fontFamily: "var(--sp-font-mono)" }}>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 14 }}>50</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 14 }}>100</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 14 }}>200</span>
                    <span style={{ color: "var(--sp-fg-4)" }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 16, fontWeight: 700 }}>400 ₽</span>
                  </div>
                )}
              </div>
              <SPSwitch checked={prog} onChange={setProg} />
            </div>
          </SPCard>
        </div>

      </div>
    </div>
  );
}

/* ============================================================
   STREAK MODAL v2
   ============================================================ */
function StreakModalV2() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      {/* dimmed underlying screen hint */}
      <div style={{
        position: "absolute", inset: 0,
        background: "linear-gradient(180deg, rgba(6,9,18,.92) 0%, rgba(6,9,18,.85) 100%)",
      }} />
      {/* glow */}
      <div style={{
        position: "absolute", left: "50%", bottom: 100, transform: "translateX(-50%)",
        width: 400, height: 400, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.30) 0%, transparent 60%)",
        filter: "blur(40px)",
      }} />

      <SPStatusBar time="7:01" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: "0 12px 16px" }}>
        <div style={{
          background: "var(--sp-bg-2)", borderRadius: 28, padding: 28,
          textAlign: "center", position: "relative", overflow: "hidden",
          border: "1px solid rgba(46,219,159,.20)",
          boxShadow: "0 -20px 60px -10px rgba(46,219,159,.20)",
        }}>
          {/* corner glow */}
          <div style={{
            position: "absolute", top: -60, right: -60,
            width: 200, height: 200, borderRadius: "50%",
            background: "radial-gradient(circle, rgba(46,219,159,.18) 0%, transparent 70%)",
          }}/>

          <div style={{
            width: 96, height: 96, borderRadius: 28,
            background: "var(--sp-grad-money)", margin: "0 auto",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "0 12px 40px rgba(46,219,159,.40)", position: "relative",
          }}>
            <IconFlame size={48} style={{ color: "#052016" }} />
          </div>

          <div className="sp-caps" style={{ marginTop: 20, color: "var(--sp-money-300)" }}>Серия · 7 дней без откладываний</div>

          <div style={{
            font: "var(--sp-t-money-xl)", marginTop: 8,
            background: "var(--sp-grad-money)", WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent",
            letterSpacing: "-.02em",
          }}>
            +350 ₽
          </div>
          <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-1)", marginTop: 4 }}>
            Сэкономили за неделю
          </div>
          <div className="sp-body" style={{ marginTop: 8, color: "var(--sp-fg-3)", maxWidth: 280, margin: "8px auto 0" }}>
            Деньги вернули на баланс. Потратьте их на следующей слабой неделе.
          </div>

          {/* Days streak */}
          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 24 }}>
            {[1,2,3,4,5,6,7].map(d => (
              <div key={d} style={{
                width: 32, height: 32, borderRadius: 10,
                background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
                display: "flex", alignItems: "center", justifyContent: "center",
                font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)",
              }}>
                {d}
              </div>
            ))}
          </div>

          <div style={{ marginTop: 24, display: "flex", flexDirection: "column", gap: 10 }}>
            <SPButton variant="money" size="lg" full>Поделиться победой</SPButton>
            <SPButton variant="quiet" size="md" full>Закрыть</SPButton>
          </div>
        </div>
      </div>
    </div>
  );
}

/* expose */
Object.assign(window, {
  Phone, PulseDot,
  FiringDawn, FiringMoneyFirst, FiringMinimal, FiringNoBalanceV2,
  AlarmsListV2, WalletV2, CreateAlarmV2, StreakModalV2,
});
