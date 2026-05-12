// SnoozePay — макеты экранов (BEFORE/AFTER) и пиксельные имитации.
// Все before-экраны воспроизводят ОШИБКИ из figma:
//  - generic iOS blue-кнопки;
//  - центрированный текст без иерархии;
//  - smacked spacing 16/12/20 россыпью;
//  - "плоские" карточки в light-mode;
//  - snooze не отличается от обычной CTA.
// After-экраны — фикс по новой системе.

const { useState: useS } = React;

/* ============================================================
   Каркас экрана — статус-бар + content scroll
   ============================================================ */
function Screen({ children, theme = "dark", bg, statusTone, time = "7:00", noStatus }) {
  const lightStatus = (theme === "light" && statusTone !== "dark") ? "dark" : "light";
  return (
    <div data-theme={theme} className="phone__screen" style={{ background: bg || "var(--sp-bg-0)" }}>
      {!noStatus && <SPStatusBar time={time} tone={lightStatus} />}
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column" }}>
        {!noStatus && <div style={{ height: 54 }} />}
        {children}
      </div>
    </div>
  );
}

/* ============================================================
   1. ALARM FIRING (срабатывание) — до/после
   ============================================================ */
function FiringBefore() {
  return (
    <Screen theme="dark" bg="#0A0F1F">
      <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "space-between", padding: "60px 20px 40px", textAlign: "center", color: "#fff" }}>
        <div>
          <div style={{ fontSize: 14, opacity: .6 }}>Пятница, 27 апреля</div>
          <div style={{ fontSize: 80, fontWeight: 300, fontFamily: "Manrope", margin: "20px 0", letterSpacing: "-.02em" }}>7:00</div>
          <div style={{ fontSize: 18, opacity: .8 }}>Будильник</div>
        </div>
        {/* generic ios-style buttons — basic blue & red */}
        <div style={{ width: "100%", display: "flex", flexDirection: "column", gap: 12 }}>
          <button style={{ height: 50, borderRadius: 12, border: 0, background: "#0A84FF", color: "#fff", fontSize: 17, fontWeight: 600 }}>Отложить (50 ₽)</button>
          <button style={{ height: 50, borderRadius: 12, border: 0, background: "#FF453A", color: "#fff", fontSize: 17, fontWeight: 600 }}>Выключить</button>
        </div>
      </div>
    </Screen>
  );
}

function FiringAfter({ progressive }) {
  const price = progressive ? 200 : 50;
  const tone = progressive ? "pain" : "warn";
  return (
    <Screen theme="dark" bg="var(--sp-grad-dawn)" time="7:00">
      <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: "20px 20px 32px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)" }}>Пятница, 27 апреля · Подъём</div>
          <div style={{ font: "var(--sp-t-clock-xl)", color: "#FFF", marginTop: 16, letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums" }}>7:00</div>
          <div style={{ marginTop: 32, display: "flex", alignItems: "center", gap: 10 }}>
            <SPPill tone="money" icon={<IconCoin size={14}/>}>Баланс {fmtRub(840)}</SPPill>
            {progressive && <SPPill tone="pain" icon={<IconFlame size={14}/>}>Прогрессив ×4</SPPill>}
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <SPSnoozePrice
            price={price}
            tone={tone}
            minutes={5}
            hint={progressive ? `Следующее откладывание: ${fmtRub(price * 2)}` : "Цена фиксированная"}
          />
          <SPButton variant="ghost" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </Screen>
  );
}

function FiringNoBalance() {
  return (
    <Screen theme="dark" bg="var(--sp-grad-dawn)">
      <div style={{ flex: 1, display: "flex", flexDirection: "column", padding: "20px 20px 32px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)" }}>Пятница, 27 апреля · Подъём</div>
          <div style={{ font: "var(--sp-t-clock-xl)", color: "#FFF", marginTop: 16, letterSpacing: "-.04em" }}>7:00</div>
          <div style={{ marginTop: 24 }}>
            <SPPill tone="pain" icon={<IconCoin size={14}/>}>Баланс 0 ₽</SPPill>
          </div>
          <div style={{ marginTop: 16, color: "rgba(255,255,255,.7)", maxWidth: 280, font: "var(--sp-t-body-lg)" }}>
            Откладывать больше не получится. Только встать.
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <SPSnoozePrice price={50} disabled minutes={5} hint="Недостаточно средств" />
          <SPButton variant="money" size="lg" full>Я встал — выключить</SPButton>
        </div>
      </div>
    </Screen>
  );
}

/* ============================================================
   2. WALLET / DEPOSIT — до/после
   ============================================================ */
function WalletBefore() {
  return (
    <Screen theme="light" bg="#F2F2F7">
      <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <button style={{ background: "none", border: 0, color: "#0A84FF", fontSize: 17 }}>‹ Назад</button>
        <div style={{ fontSize: 17, fontWeight: 600 }}>Кошелёк</div>
        <div style={{ width: 50 }}/>
      </div>
      <div style={{ padding: 20, display: "flex", flexDirection: "column", gap: 16 }}>
        <div style={{ background: "#fff", borderRadius: 12, padding: 16, textAlign: "center" }}>
          <div style={{ fontSize: 13, color: "#8E8E93" }}>Текущий баланс</div>
          <div style={{ fontSize: 30, fontWeight: 600, marginTop: 4 }}>840 ₽</div>
        </div>
        {/* плоская сетка — все равноправные */}
        <div style={{ fontSize: 15, fontWeight: 600, marginTop: 4 }}>Пополнить</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
          {[100, 300, 500, 1000, 2000, 5000].map(v => (
            <button key={v} style={{ height: 64, background: "#fff", border: "1px solid #E5E5EA", borderRadius: 12, fontSize: 16 }}>{v} ₽</button>
          ))}
        </div>
        <button style={{ height: 50, background: "#0A84FF", color: "#fff", border: 0, borderRadius: 12, fontSize: 17, fontWeight: 600, marginTop: 8 }}>Купить</button>
        <div style={{ fontSize: 13, color: "#8E8E93", textAlign: "center" }}>Apple Pay</div>
      </div>
    </Screen>
  );
}

function WalletAfter() {
  const [sel, set] = useS(500);
  return (
    <Screen theme="dark" bg="var(--sp-bg-0)">
      <SPNavBar
        large
        title="Кошелёк"
        leading={<button><IconBack size={18}/></button>}
        trailing={<button><IconChart size={18}/></button>}
      />
      <div style={{ padding: "0 20px", display: "flex", flexDirection: "column", gap: 24, flex: 1, overflow: "hidden" }}>

        <SPBalanceCard balance={840} delta={-160} hint="При текущей цене откладывания хватит на ~17 откладываний" />

        <div>
          <div className="sp-caps" style={{ marginBottom: 12 }}>Пополнить — выберите сумму</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 10 }}>
            <SPAmountPreset value={100}  label="≈ 2 откладывания"  selected={sel===100}  onClick={()=>set(100)} />
            <SPAmountPreset value={500}  label="≈ 10 откладываний" popular selected={sel===500}  onClick={()=>set(500)} />
            <SPAmountPreset value={1000} label="≈ 20 откладываний" selected={sel===1000} onClick={()=>set(1000)} />
            <SPAmountPreset value={2000} label="≈ 40 откладываний" selected={sel===2000} onClick={()=>set(2000)} />
            <SPAmountPreset value={5000} label="на месяц"    selected={sel===5000} onClick={()=>set(5000)} />
            <SPAmountPreset value={10000} label="макс."      selected={sel===10000} onClick={()=>set(10000)} />
          </div>
        </div>

        <div style={{ marginTop: "auto", paddingBottom: 28, display: "flex", flexDirection: "column", gap: 10 }}>
          <SPButton variant="money" size="lg" full
            icon={<IconShield size={18}/>}
            suffix={fmtRub(sel)}>
            Пополнить через Apple Pay
          </SPButton>
          <div className="sp-meta" style={{ textAlign: "center" }}>StoreKit · покупка не возвращается, штрафы списываются с баланса</div>
        </div>
      </div>
    </Screen>
  );
}

/* ============================================================
   3. ALARMS LIST (главный) — после
   ============================================================ */
function AlarmsListAfter() {
  return (
    <Screen theme="dark">
      <SPNavBar
        large
        title="Будильники"
        trailing={<button><IconPlus size={20}/></button>}
      />
      <div style={{ padding: "0 20px", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflow: "hidden" }}>

        <SPCard tone="raised" padding={20} radius={20}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div className="sp-caps">Будни · 5 дней</div>
            <SPSwitch checked={true} onChange={()=>{}} />
          </div>
          <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-1)", letterSpacing: "-.03em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>7:00</div>
          <div style={{ display: "flex", gap: 8, marginTop: 14, flexWrap: "wrap" }}>
            <SPPill icon={<IconCoin size={12}/>} tone="warn">50 ₽ за поспать ещё</SPPill>
            <SPPill icon={<IconFlame size={12}/>} tone="pain">Прогрессив</SPPill>
            <SPPill icon={<IconSound size={12}/>}>Soft Dawn</SPPill>
          </div>
        </SPCard>

        <SPCard tone="surface" padding={20} radius={20}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-4)" }}>Выходные · Сб, Вс</div>
            <SPSwitch checked={false} onChange={()=>{}} />
          </div>
          <div style={{ font: "var(--sp-t-clock-lg)", color: "var(--sp-fg-3)", letterSpacing: "-.03em", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>9:30</div>
          <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
            <SPPill>20 ₽ за поспать ещё</SPPill>
            <SPPill>Birds</SPPill>
          </div>
        </SPCard>

        <div style={{ marginTop: "auto" }}>
          <SPTabBar active="alarms" />
        </div>
      </div>
    </Screen>
  );
}

/* ============================================================
   4. CREATE ALARM — после
   ============================================================ */
function CreateAlarmAfter() {
  const [prog, setProg] = useS(true);
  return (
    <Screen theme="dark">
      <SPNavBar
        title="Новый будильник"
        leading={<button><IconClose size={18}/></button>}
        trailing={<SPButton variant="money" size="sm">Создать</SPButton>}
      />
      <div style={{ padding: "0 20px", display: "flex", flexDirection: "column", gap: 20, flex: 1, overflowY: "auto" }}>

        <div style={{ textAlign: "center", padding: "8px 0 16px" }}>
          <div style={{ font: "var(--sp-t-clock-xl)", color: "var(--sp-fg-1)", letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums" }}>
            <span>07</span><span style={{ opacity: .35, padding: "0 6px" }}>:</span><span>00</span>
          </div>
        </div>

        <SPCard padding={4} radius={20}>
          <SPRow
            divider={false}
            leading={<IconClock size={20}/>}
            title="Повтор"
            trailing={<><span className="sp-meta">Будни</span><IconChevR size={16}/></>}
          />
          <SPRow
            leading={<IconSound size={20}/>}
            title="Звук"
            trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}
          />
          <SPRow
            leading={<IconCoin size={20}/>}
            title="Цена откладывания"
            subtitle="Сколько спишется при «отложить»"
            trailing={<><span className="sp-mono" style={{ color: "var(--sp-warn-400)" }}>50 ₽</span><IconChevR size={16}/></>}
          />
        </SPCard>

        <SPCard padding={20} radius={20} tone={prog ? "outline" : "surface"}
          style={prog ? { borderColor: "var(--sp-stroke-pain)" } : {}}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
            <div style={{ flex: 1 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <IconFlame size={18} style={{ color: "var(--sp-pain-400)" }}/>
                <div className="sp-h4">Прогрессивный режим</div>
              </div>
              <div className="sp-meta" style={{ marginTop: 6 }}>
                Каждый следующее откладывание — в 2 раза дороже. Сегодня: 50 → 100 → 200 → 400 ₽.
              </div>
            </div>
            <SPSwitch checked={prog} onChange={setProg} />
          </div>
        </SPCard>

      </div>
    </Screen>
  );
}

/* ============================================================
   5. STREAK MODAL
   ============================================================ */
function StreakModal() {
  return (
    <Screen theme="dark" bg="var(--sp-grad-dawn)">
      <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: 16 }}>
        <SPCard tone="raised" padding={28} radius={28} style={{ textAlign: "center" }}>
          <div style={{ width: 84, height: 84, borderRadius: 24, background: "var(--sp-grad-money)", margin: "0 auto", display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "var(--sp-shadow-money)" }}>
            <IconFlame size={40} style={{ color: "#052016" }}/>
          </div>
          <div className="sp-caps" style={{ marginTop: 18, color: "var(--sp-money-300)" }}>7 дней без откладываний</div>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", marginTop: 6 }}>Сэкономили 350 ₽</div>
          <div className="sp-body" style={{ marginTop: 8, color: "var(--sp-fg-3)" }}>
            Вернули на баланс. Потратьте на следующей слабой неделе.
          </div>
          <div style={{ marginTop: 24, display: "flex", flexDirection: "column", gap: 10 }}>
            <SPButton variant="money" size="lg" full>Поделиться</SPButton>
            <SPButton variant="quiet" size="md" full>Закрыть</SPButton>
          </div>
        </SPCard>
      </div>
    </Screen>
  );
}

/* expose */
Object.assign(window, {
  Screen,
  FiringBefore, FiringAfter, FiringNoBalance,
  WalletBefore, WalletAfter,
  AlarmsListAfter, CreateAlarmAfter, StreakModal,
});
