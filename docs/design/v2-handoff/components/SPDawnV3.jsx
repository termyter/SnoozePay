// SnoozePay · Dawn v3 — атмосферный язык, расширенный до всех экранов.
// Ключи:
//  - "Living glow" внизу экрана — медленно дышит (8s ease-in-out).
//  - Время появляется fade+blur за 800мс на mount.
//  - Цена откладывания мягко пульсирует свечением (без скачков шрифта).
//  - При нажатии: scale .96 + pain-flash на балансе + "−50 ₽" вылетает вверх.
//  - Прогрессив: фон смещается в красный, сверху — тиккеры предыдущих откладываний.

const { useState: usS, useEffect: usE, useRef: usR, useMemo: usM } = React;

/* ============================================================
   Dawn shell — фоновая атмосфера, общая для всех Dawn-экранов
   tone: "calm"     (обычный сон, тёплый янтарь)
         "tense"    (прогрессив, цвет смещается в красный)
         "drained"  (баланс кончился, фон холоднее)
         "morning"  (после стрика — мятный рассвет)
   ============================================================ */
function DawnAtmosphere({ tone = "calm" }) {
  const palettes = {
    calm:    { sun: "rgba(255,184,77,.45)", haze: "rgba(245,158,11,.10)", base: "linear-gradient(180deg, #0A0E1A 0%, #0E1320 55%, #1A1410 100%)" },
    tense:   { sun: "rgba(244,82,63,.42)",  haze: "rgba(212,58,40,.12)",  base: "linear-gradient(180deg, #0A0E1A 0%, #14101C 50%, #240C0C 100%)" },
    drained: { sun: "rgba(120,140,180,.18)",haze: "rgba(60,80,120,.06)",  base: "linear-gradient(180deg, #08091A 0%, #0B0F1F 50%, #100D18 100%)" },
    morning: { sun: "rgba(46,219,159,.30)", haze: "rgba(94,234,184,.08)", base: "linear-gradient(180deg, #0A0E1A 0%, #0D1620 55%, #0A1F19 100%)" },
  };
  const p = palettes[tone];
  return (
    <>
      <div style={{ position: "absolute", inset: 0, background: p.base }} />
      {/* Living glow — дышит */}
      <div className="dawn-glow" style={{
        position: "absolute", left: "50%", bottom: "-180px", transform: "translateX(-50%)",
        width: 480, height: 480, borderRadius: "50%",
        background: `radial-gradient(circle, ${p.sun} 0%, ${p.haze} 35%, transparent 70%)`,
        filter: "blur(20px)",
      }} />
      {/* стартовое затемнение по краям, чтобы фокус был в центре */}
      <div style={{
        position: "absolute", inset: 0, pointerEvents: "none",
        background: "radial-gradient(120% 80% at 50% 60%, transparent 40%, rgba(0,0,0,.35) 100%)",
      }} />
    </>
  );
}

/* ============================================================
   Animated time — fade+blur на mount, tabular-nums чтобы не прыгало
   ============================================================ */
function DawnTime({ value = "07:00", small }) {
  const [shown, setShown] = usS(false);
  usE(() => {
    const t = setTimeout(() => setShown(true), 80);
    return () => clearTimeout(t);
  }, []);
  return (
    <div style={{
      font: small ? "200 64px/64px var(--sp-font-mono)" : "var(--sp-t-clock-xl)",
      color: "#FFF", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums",
      textShadow: "0 4px 60px rgba(255,184,77,.20)",
      filter: shown ? "blur(0px)" : "blur(12px)",
      opacity: shown ? 1 : 0,
      transform: shown ? "translateY(0)" : "translateY(8px)",
      transition: "filter 800ms var(--sp-ease-out), opacity 800ms var(--sp-ease-out), transform 800ms var(--sp-ease-out)",
    }}>
      {value}
    </div>
  );
}

/* ============================================================
   Snooze price button — Dawn-edition
   - подсветка пульсирует за счёт box-shadow на ::before
   - tabular-nums чтобы цифра не прыгала
   - на нажатии: scale + halo
   ============================================================ */
function DawnSnoozeButton({ price, tone = "warn", minutes = 5, hint, disabled, onClick, pressed }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`dawn-snooze dawn-snooze--${tone} ${disabled ? "is-disabled" : ""} ${pressed ? "is-pressed" : ""}`}
    >
      <div className="dawn-snooze__caps">
        <IconClock size={14}/>
        Спать ещё {minutes} мин
      </div>
      <div className="dawn-snooze__price">
        −{Math.round(price).toLocaleString("ru-RU")}<span className="dawn-snooze__cur">₽</span>
      </div>
      {hint && <div className="dawn-snooze__hint">{hint}</div>}
    </button>
  );
}

/* ============================================================
   Balance pill — с поведением «деньги уходят»
   ============================================================ */
function BalancePill({ balance, deduct, tone = "money" }) {
  const isLost = tone === "pain" || balance === 0;
  return (
    <div className={`dawn-bal ${isLost ? "is-lost" : ""}`}>
      <IconCoin size={12} />
      <span className="dawn-bal__label">Баланс</span>
      <span className="dawn-bal__value">{Math.round(balance).toLocaleString("ru-RU")} ₽</span>
      {deduct && (
        <span key={deduct.id} className="dawn-bal__fly">−{deduct.amount} ₽</span>
      )}
    </div>
  );
}

/* ============================================================
   Tickers row — миниатюрная история сегодняшних откладываний
   ============================================================ */
function TickerRow({ history }) {
  if (!history || history.length === 0) return null;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 16, justifyContent: "center" }}>
      <span className="sp-caps" style={{ color: "rgba(255,255,255,.45)", letterSpacing: ".18em" }}>сегодня</span>
      <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
        {history.map((h, i) => (
          <React.Fragment key={i}>
            <span style={{
              padding: "3px 8px", borderRadius: 999,
              background: h.amount >= 200 ? "rgba(244,82,63,.18)" : "rgba(245,158,11,.18)",
              color: h.amount >= 200 ? "var(--sp-pain-300)" : "var(--sp-warn-300)",
              fontFamily: "var(--sp-font-mono)", fontSize: 11, fontWeight: 600,
            }}>
              −{h.amount}
            </span>
            {i < history.length - 1 && <span style={{ color: "rgba(255,255,255,.25)", fontSize: 10 }}>·</span>}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

/* ============================================================
   FIRING — Dawn v3 — интерактивный с двумя путями
   ============================================================ */
function FiringDawnV3() {
  const [state, setState] = usS("idle"); // idle, snoozing, woke
  const [snoozes, setSnoozes] = usS(0);  // 0..N
  const [balance, setBalance] = usS(840);
  const [deduct, setDeduct] = usS(null);
  const [time, setTime] = usS("07:00");
  const progressive = true;

  const prices = [50, 100, 200, 400];
  const idx = Math.min(snoozes, prices.length - 1);
  const price = prices[idx];
  const nextPrice = idx < prices.length - 1 ? prices[idx + 1] : null;
  // Кнопка остаётся золотой (warn) на всех ступенях — для тревожности
  // используем индикатор «Прогрессив» и фон, не цвет CTA.
  const tone = "warn";

  const history = usM(() => prices.slice(0, snoozes).map(a => ({ amount: a })), [snoozes]);

  const onSnooze = () => {
    if (balance < price) return;
    setState("snoozing");
    setDeduct({ id: Date.now(), amount: price });
    setBalance(b => b - price);
    setTimeout(() => setDeduct(null), 1500);
    setTimeout(() => {
      setSnoozes(s => s + 1);
      const m = parseInt(time.split(":")[1]) + 5;
      setTime(`07:${String(m).padStart(2, "0")}`);
      setState("idle");
    }, 800);
  };

  const onWake = () => {
    setState("woke");
  };

  const reset = () => {
    setState("idle"); setSnoozes(0); setBalance(840); setTime("07:00"); setDeduct(null);
  };

  // wake state — отдельный экран
  if (state === "woke") return <WokeScreen savedFrom={840 - balance} reset={reset} snoozes={snoozes} />;

  // determine atmosphere tone
  const atmTone = balance === 0 ? "drained" : (price >= 200 ? "tense" : "calm");

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <DawnAtmosphere tone={atmTone} />

      <SPStatusBar time={time} tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column" }}>
        {/* HEADER: дата + балланс */}
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span className="sp-caps" style={{ color: "rgba(255,255,255,.55)" }}>Пт · 27 апр</span>
          </div>
          <BalancePill
            balance={balance}
            deduct={deduct}
            tone={balance === 0 ? "pain" : "money"}
          />
        </div>

        {/* CENTER: время + контекст */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", padding: "0 16px", textAlign: "center" }}>

          <DawnTime value={time} />

          <div className="sp-caps" style={{ color: "rgba(255,255,255,.45)", marginTop: 12, letterSpacing: ".18em" }}>
            {balance === 0 ? "только встать" : "пора вставать"}
          </div>

          {/* progressive indicator */}
          {progressive && snoozes > 0 && (
            <div style={{ marginTop: 22, display: "inline-flex", alignItems: "center", gap: 8, padding: "6px 12px", borderRadius: 999, background: "rgba(244,82,63,.14)", border: "1px solid rgba(244,82,63,.28)" }}>
              <PulseDot color="rgba(244,82,63,.7)" />
              <span className="sp-caps" style={{ color: "var(--sp-pain-300)", letterSpacing: ".18em" }}>
                Прогрессив · {snoozes + 1}-й поспать ещё
              </span>
            </div>
          )}

          <TickerRow history={history} />
        </div>

        {/* CTA */}
        <div style={{ padding: "0 16px 32px", display: "flex", flexDirection: "column", gap: 10 }}>
          <DawnSnoozeButton
            price={price}
            tone={tone}
            minutes={5}
            disabled={balance < price}
            pressed={state === "snoozing"}
            onClick={onSnooze}
            hint={
              balance < price
                ? "Баланса не хватает"
                : nextPrice
                  ? `следующее откладывание: ${nextPrice} ₽`
                  : "максимум — дальше только встать"
            }
          />
          <button
            onClick={onWake}
            className="dawn-wake"
            style={{
              background: balance === 0 ? "var(--sp-grad-money)" : "transparent",
              color: balance === 0 ? "var(--sp-fg-on-money)" : "rgba(255,255,255,.85)",
              border: balance === 0 ? "0" : "1.5px solid rgba(255,255,255,.18)",
              boxShadow: balance === 0 ? "var(--sp-shadow-money)" : "none",
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

/* ============================================================
   Woke screen — после нажатия «Я встал»
   ============================================================ */
function WokeScreen({ savedFrom, snoozes, reset }) {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <DawnAtmosphere tone="morning" />
      <SPStatusBar time="7:00" tone="light" />
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", padding: "54px 16px 32px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center", gap: 14 }}>
          <div style={{
            width: 84, height: 84, borderRadius: 24,
            background: "var(--sp-grad-money)",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "0 12px 40px rgba(46,219,159,.40)",
          }}>
            <IconCheck size={40} style={{ color: "#052016", strokeWidth: 3 }} />
          </div>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)", marginTop: 8 }}>Доброе утро</div>
          <div style={{ font: "var(--sp-t-h1)", color: "#FFF" }}>
            {snoozes === 0 ? "Встал с первого раза" : `Удержались после ${snoozes} откладываний`}
          </div>
          <div className="sp-body-lg" style={{ color: "rgba(255,255,255,.65)", maxWidth: 280 }}>
            {snoozes === 0
              ? "Баланс в полной сохранности. Так держать."
              : `Сегодня списано ${savedFrom} ₽. Завтра попробуем не списать ничего.`}
          </div>
        </div>
        <SPButton variant="quiet" size="md" full onClick={reset}>Сбросить демо</SPButton>
      </div>
    </div>
  );
}

/* ============================================================
   PulseDot — отдельный
   ============================================================ */
function PulseDotV2({ color = "rgba(255,184,77,.6)" }) {
  return (
    <span style={{
      display: "inline-block", width: 8, height: 8, borderRadius: "50%",
      background: color, color: color,
      animation: "sp-pulse 1.6s var(--sp-ease-out) infinite",
    }} />
  );
}
window.PulseDot = window.PulseDot || PulseDotV2;

/* ============================================================
   ALARMS LIST — Dawn family
   Тёплый акцент сверху, остальное тёмное
   ============================================================ */
function AlarmsListDawn() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* субтильный warm-glow в шапке как «отголосок» Dawn */}
      <div style={{
        position: "absolute", top: -100, right: -80,
        width: 280, height: 280, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.10) 0%, transparent 70%)",
        filter: "blur(30px)", pointerEvents: "none",
      }}/>

      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", position: "relative" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Доброе утро</div>
            <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Будильники</div>
          </div>
          <button style={{
            width: 44, height: 44, borderRadius: 22, border: 0,
            background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
            display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
            boxShadow: "var(--sp-shadow-money)",
          }}>
            <IconPlus size={22} />
          </button>
        </div>

        <div style={{ padding: "16px 16px 0" }}>
          <div style={{
            padding: "16px", borderRadius: 18,
            background: "linear-gradient(135deg, rgba(46,219,159,.14) 0%, rgba(46,219,159,.02) 100%)",
            border: "1px solid rgba(46,219,159,.20)",
            display: "flex", alignItems: "center", gap: 14,
            position: "relative", overflow: "hidden",
          }}>
            <div style={{
              width: 44, height: 44, borderRadius: 12, background: "var(--sp-grad-money)",
              display: "flex", alignItems: "center", justifyContent: "center",
              flexShrink: 0,
            }}>
              <IconFlame size={22} style={{ color: "#052016" }} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
                <span style={{ font: "var(--sp-t-h3)", color: "#FFF", fontFamily: "var(--sp-font-mono)" }}>5</span>
                <span className="sp-caps" style={{ color: "var(--sp-money-300)" }}>дней без откладываний</span>
              </div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-2)", marginTop: 2 }}>
                Сэкономили <span style={{ fontFamily: "var(--sp-font-mono)", color: "var(--sp-money-300)" }}>+{fmtRub(250)}</span> · до недели 2 дня
              </div>
            </div>
            <IconChevR size={18} style={{ color: "var(--sp-fg-3)" }} />
          </div>
        </div>

        <div style={{ padding: "20px 16px 0", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflowY: "auto" }}>
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
              <SPPill tone="warn" icon={<IconCoin size={12}/>}>{fmtRub(50)}</SPPill>
              <SPPill tone="pain" icon={<IconFlame size={12}/>}>Прогрессив ×2</SPPill>
              <SPPill icon={<IconSound size={12}/>}>Soft Dawn</SPPill>
            </div>
          </SPCard>

          <SPCard tone="surface" padding={20} radius={20}>
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Выходные · Сб, Вс</div>
                <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.04em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                  9:30
                </div>
              </div>
              <SPSwitch checked={false} onChange={()=>{}} />
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
              <SPSwitch checked={false} onChange={()=>{}} />
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 14 }}>
              <SPPill tone="warn">{fmtRub(100)}</SPPill>
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
   WALLET — Dawn family
   ============================================================ */
function WalletDawn() {
  const [sel, setSel] = usS(500);
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      {/* warm hint в углу */}
      <div style={{
        position: "absolute", top: -120, left: -80,
        width: 320, height: 320, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.14) 0%, transparent 70%)",
        filter: "blur(30px)",
      }}/>

      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", position: "relative" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Баланс</div>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconChart size={18}/>
          </button>
        </div>

        <div style={{ padding: "16px 16px 0" }}>
          <SPBalanceCard balance={840} delta={-160} hint="Хватит на ~17 откладываний при текущей цене" />
        </div>

        <div style={{ padding: "20px 16px 0", flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 10 }}>
            <div className="sp-caps">Положить под расписку</div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Apple Pay</div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
            <SPAmountPreset value={100}  label="≈ 2 откладывания"   selected={sel===100}  onClick={()=>setSel(100)} />
            <SPAmountPreset value={500}  label="≈ 10 откладываний" popular selected={sel===500}  onClick={()=>setSel(500)} />
            <SPAmountPreset value={1000} label="≈ 20 откладываний" selected={sel===1000} onClick={()=>setSel(1000)} />
            <SPAmountPreset value={2000} label="≈ 40 откладываний" selected={sel===2000} onClick={()=>setSel(2000)} />
            <SPAmountPreset value={5000} label="на месяц"    selected={sel===5000} onClick={()=>setSel(5000)} />
            <SPAmountPreset value={10000} label="макс."      selected={sel===10000} onClick={()=>setSel(10000)} />
          </div>

          <div style={{ marginTop: 22, paddingBottom: 12 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
              <div className="sp-caps">Потери — последние 7 дней</div>
              <div className="sp-meta" style={{ fontFamily: "var(--sp-font-mono)", color: "var(--sp-pain-400)" }}>−{fmtRub(160)}</div>
            </div>
            <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 56 }}>
              {[40, 0, 80, 50, 0, 0, 30].map((v, i) => (
                <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
                  <div style={{
                    width: "100%", height: v ? `${v}%` : 4,
                    borderRadius: 4, minHeight: 4,
                    background: v ? "var(--sp-grad-pain)" : "var(--sp-white-08)",
                    opacity: v ? 1 : .5,
                  }} />
                  <div style={{ font: "10px/14px var(--sp-font-body)", color: "var(--sp-fg-4)", fontWeight: 500 }}>
                    {["П","В","С","Ч","П","С","В"][i]}
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div style={{ marginTop: "auto", paddingBottom: 16, display: "flex", flexDirection: "column", gap: 8 }}>
            <SPButton variant="money" size="lg" full icon={<IconWallet size={20}/>} suffix={fmtRubTight(sel)}>
              Пополнить
            </SPButton>
            <div className="sp-meta" style={{ textAlign: "center", color: "var(--sp-fg-4)" }}>
              Покупка не возвращается · штрафы списываются с баланса
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   CREATE ALARM — Dawn family
   ============================================================ */
function CreateAlarmDawn() {
  const [prog, setProg] = usS(true);
  const [price, setPrice] = usS(50);
  const days = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];
  const [active, setActive] = usS(new Set([0,1,2,3,4]));
  const toggle = (i) => {
    const n = new Set(active);
    n.has(i) ? n.delete(i) : n.add(i);
    setActive(n);
  };

  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <div style={{
        position: "absolute", top: -100, left: "50%", transform: "translateX(-50%)",
        width: 360, height: 280, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.12) 0%, transparent 70%)",
        filter: "blur(30px)",
      }}/>

      <SPStatusBar time="9:42" tone="light" />
      <div style={{ flex: 1, display: "flex", flexDirection: "column", position: "relative" }}>

        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconClose size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Новый будильник</div>
          <SPButton variant="money" size="sm">Готово</SPButton>
        </div>

        {/* Wheel-time picker */}
        <div style={{ padding: "16px 16px 0", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 4 }}>Подъём</div>
          <div style={{ display: "inline-flex", alignItems: "baseline", gap: 0 }}>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>07</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-4)", padding: "0 4px" }}>:</span>
            <span style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.05em", fontVariantNumeric: "tabular-nums" }}>00</span>
          </div>
          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 12 }}>
            {days.map((d, i) => {
              const on = active.has(i);
              return (
                <button key={d} onClick={()=>toggle(i)} style={{
                  width: 36, height: 36, borderRadius: 18, border: 0,
                  background: on ? "var(--sp-grad-money)" : "var(--sp-white-06)",
                  color: on ? "var(--sp-fg-on-money)" : "var(--sp-fg-3)",
                  font: "var(--sp-t-button-sm)", cursor: "pointer",
                  transition: "all 200ms var(--sp-ease-out)",
                }}>{d}</button>
              );
            })}
          </div>
        </div>

        <div style={{ padding: "20px 16px 0", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflowY: "auto" }}>
          <SPCard padding="4px 20px" radius={20}>
            <SPRow
              divider={false}
              leading={<IconSound size={20} style={{ color: "var(--sp-fg-3)" }}/>}
              title="Звук"
              trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}
            />
            <SPRow
              leading={<IconBell size={20} style={{ color: "var(--sp-fg-3)" }}/>}
              title="Вибрация"
              trailing={<SPSwitch checked={true} onChange={()=>{}}/>}
            />
          </SPCard>

          {/* Snooze price */}
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 14 }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Цена откладывания</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Сколько спишется при «отложить»</div>
              </div>
              <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-warn-400)" }}>
                {fmtRub(price)}
              </div>
            </div>
            <div style={{ display: "flex", gap: 6 }}>
              {[20, 50, 100, 200, 500].map(v => (
                <button key={v} onClick={()=>setPrice(v)} style={{
                  flex: 1, height: 40, borderRadius: 12, border: 0, cursor: "pointer",
                  background: price === v ? "var(--sp-grad-warn)" : "var(--sp-white-06)",
                  color: price === v ? "var(--sp-fg-on-warn)" : "var(--sp-fg-2)",
                  font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)",
                  transition: "all 160ms var(--sp-ease-out)",
                }}>
                  {v}
                </button>
              ))}
            </div>
          </SPCard>

          {/* Progressive */}
          <SPCard padding={20} radius={20}
            style={prog ? { background: "linear-gradient(135deg, rgba(244,82,63,.10), rgba(244,82,63,.02))", border: "1px solid rgba(244,82,63,.25)", boxShadow: "none" } : { boxShadow: "none" }}>
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
                  <div style={{ marginTop: 12, display: "flex", gap: 6, alignItems: "center", fontFamily: "var(--sp-font-mono)", flexWrap: "wrap" }}>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 13 }}>{price}</span>
                    <span style={{ color: "var(--sp-fg-4)", fontSize: 11 }}>→</span>
                    <span style={{ color: "var(--sp-warn-400)", fontSize: 13 }}>{price*2}</span>
                    <span style={{ color: "var(--sp-fg-4)", fontSize: 11 }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 13 }}>{price*4}</span>
                    <span style={{ color: "var(--sp-fg-4)", fontSize: 11 }}>→</span>
                    <span style={{ color: "var(--sp-pain-400)", fontSize: 16, fontWeight: 700 }}>{price*8} ₽</span>
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
   STREAK MODAL — Dawn family
   ============================================================ */
function StreakModalDawn() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(6,9,18,.92) 0%, rgba(6,9,18,.85) 100%)" }} />
      <div style={{
        position: "absolute", left: "50%", bottom: 60, transform: "translateX(-50%)",
        width: 480, height: 480, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.30) 0%, transparent 60%)",
        filter: "blur(40px)",
      }} />

      <SPStatusBar time="7:01" tone="light" />

      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: "54px 16px 16px" }}>
        <div style={{
          background: "rgba(22,28,46,.92)", backdropFilter: "blur(20px)",
          borderRadius: 28, padding: 28, textAlign: "center",
          position: "relative", overflow: "hidden",
          border: "1px solid rgba(46,219,159,.20)",
          boxShadow: "0 -20px 60px -10px rgba(46,219,159,.20)",
        }}>
          <div style={{
            position: "absolute", top: -80, right: -80,
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

          <div className="sp-caps" style={{ marginTop: 20, color: "var(--sp-money-300)" }}>7 дней без откладываний</div>

          <div style={{
            font: "var(--sp-t-money-xl)", marginTop: 8,
            background: "var(--sp-grad-money)", WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent",
            letterSpacing: "-.02em",
          }}>
            +{fmtRub(350)}
          </div>
          <div style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-1)", marginTop: 4 }}>
            Сэкономили за неделю
          </div>
          <div className="sp-body" style={{ marginTop: 8, color: "var(--sp-fg-3)", maxWidth: 280, margin: "8px auto 0" }}>
            Деньги вернули на баланс. Потратьте их на следующей слабой неделе.
          </div>

          <div style={{ display: "flex", justifyContent: "center", gap: 6, marginTop: 24 }}>
            {[1,2,3,4,5,6,7].map(d => (
              <div key={d} style={{
                width: 32, height: 32, borderRadius: 10,
                background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
                display: "flex", alignItems: "center", justifyContent: "center",
                font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)",
              }}>{d}</div>
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
  DawnAtmosphere, DawnTime, DawnSnoozeButton, BalancePill, TickerRow,
  FiringDawnV3, WokeScreen,
  AlarmsListDawn, WalletDawn, CreateAlarmDawn, StreakModalDawn,
});
