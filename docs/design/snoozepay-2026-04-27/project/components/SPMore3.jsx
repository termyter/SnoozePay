// SnoozePay — экраны 23-26: финансы (история, баланс, вывод, способы оплаты)

const { useState: oS3 } = React;

/* 23. TRANSACTION HISTORY */
function TxHistory() {
  const [filter, setFilter] = oS3("all");
  const txs = [
    { d: "Сегодня",  list: [
      { t: "Поспать ещё · Будни 7:00", a: -50,  ts: "07:05", i: "snooze" },
      { t: "Поспать ещё · Будни 7:00", a: -100, ts: "07:14", i: "snooze" },
    ]},
    { d: "Вчера", list: [
      { t: "Пополнение баланса", a: +500, ts: "21:32", i: "topup" },
      { t: "Возврат: продержались 7 дней", a: +200, ts: "09:00", i: "refund" },
    ]},
    { d: "12 января", list: [
      { t: "Поспать ещё · Будни 7:00", a: -50,  ts: "07:08", i: "snooze" },
      { t: "Поспать ещё · Будни 7:00", a: -100, ts: "07:17", i: "snooze" },
      { t: "Поспать ещё · Будни 7:00", a: -200, ts: "07:26", i: "snooze" },
    ]},
  ];
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>История</div>
          <div style={{ width: 36 }}/>
        </div>

        {/* Summary card */}
        <div style={{ padding: "16px 20px 0" }}>
          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>За январь</div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 8 }}>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Списано</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-pain-400)", fontVariantNumeric: "tabular-nums" }}>−500 ₽</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Возвращено</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-money-400)", fontVariantNumeric: "tabular-nums" }}>+200 ₽</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Откладываний</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>9</div>
              </div>
            </div>
          </SPCard>
        </div>

        {/* Tabs */}
        <div style={{ padding: "16px 20px 0", display: "flex", gap: 8 }}>
          {[["all","Все"],["snooze","Списания"],["topup","Поступления"]].map(([id,t])=>(
            <button key={id} onClick={()=>setFilter(id)} style={{
              padding: "8px 14px", borderRadius: 999, border: 0, cursor: "pointer",
              font: "var(--sp-t-button-sm)",
              background: filter===id ? "var(--sp-fg-1)" : "var(--sp-white-06)",
              color: filter===id ? "var(--sp-bg-0)" : "var(--sp-fg-2)",
            }}>{t}</button>
          ))}
        </div>

        {/* Список */}
        <div style={{ padding: "16px 20px 20px", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {txs.map((g, gi) => (
            <div key={gi}>
              <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>{g.d}</div>
              <SPCard padding={4} radius={16}>
                {g.list.map((tx, i) => {
                  const neg = tx.a < 0;
                  const colors = {
                    snooze: { bg: "rgba(244,82,63,.14)", fg: "var(--sp-pain-400)" },
                    topup:  { bg: "rgba(43,194,140,.14)", fg: "var(--sp-money-400)" },
                    refund: { bg: "rgba(43,194,140,.14)", fg: "var(--sp-money-400)" },
                  }[tx.i];
                  return (
                    <SPRow key={i} divider={i < g.list.length - 1}
                      leading={
                        <div style={{ width: 36, height: 36, borderRadius: 12, background: colors.bg, color: colors.fg,
                          display: "flex", alignItems: "center", justifyContent: "center" }}>
                          {tx.i === "snooze" ? <IconFlame size={18}/> : tx.i === "topup" ? <IconPlus size={18}/> : <IconCheck size={18}/>}
                        </div>
                      }
                      title={tx.t}
                      subtitle={tx.ts}
                      trailing={
                        <span style={{ font: "var(--sp-t-money-md)", color: neg ? "var(--sp-pain-400)" : "var(--sp-money-400)", fontVariantNumeric: "tabular-nums" }}>
                          {neg ? "−" : "+"}{Math.abs(tx.a)} ₽
                        </span>
                      }/>
                  );
                })}
              </SPCard>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* 24. DEPOSIT (пополнить) */
/* Пополнение — BOTTOM SHEET поверх затемнённого живого кошелька (#233), а не
   отдельный полноэкранный шаг. Выбора способа оплаты в шите нет: платит
   StoreKit, экран «Способы оплаты» из MVP убран (#237/#521).
   Суммы — живые SKU 49/149/299/499/999 («Популярно» на 149), а не
   дизайнерская линейка 500/1000/2000/5000: продукты в App Store Connect
   заведены под первую (#233, п. 8). */
function Deposit() {
  const [amount, setAmount] = oS3(149);
  const presets = [
    { v: 49,  l: "≈ 1 откладывание" },
    { v: 149, l: "≈ 3 откладывания", popular: true },
    { v: 299, l: "≈ 6 откладываний" },
    { v: 499, l: "≈ 10 откладываний" },
    { v: 999, l: "≈ 20 откладываний" },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <WalletV2/>
      <div style={{ position: "absolute", inset: 0, background: "rgba(6,9,18,.55)", backdropFilter: "blur(2px)" }}/>

      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0,
        background: "var(--sp-bg-1)", borderTopLeftRadius: 28, borderTopRightRadius: 28,
        padding: "16px 20px 28px", boxShadow: "0 -24px 64px rgba(0,0,0,.5)",
      }}>
        <div style={{ width: 36, height: 4, borderRadius: 2, background: "var(--sp-white-12)", margin: "0 auto 16px" }}/>

        <div style={{ font: "var(--sp-t-h2)", color: "#FFF", letterSpacing: "-.01em" }}>Пополнить баланс</div>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 10, marginTop: 16 }}>
          {presets.map(p => (
            <SPAmountPreset key={p.v} value={p.v} label={p.l} popular={p.popular}
              selected={amount === p.v} onClick={()=>setAmount(p.v)} />
          ))}
        </div>

        <div style={{ marginTop: 20 }}>
          <SPButton variant="money" size="lg" full icon={<IconWallet size={18}/>} suffix={fmtRub(amount)}>
            Пополнить
          </SPButton>
        </div>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center", marginTop: 10 }}>
          Деньги попадают в баланс. Списываются только при откладывании.
        </div>
        <div className="sp-meta" style={{ color: "var(--sp-fg-2)", textAlign: "center", marginTop: 12, cursor: "pointer" }}>
          Восстановить покупки
        </div>
      </div>
    </div>
  );
}

/* 25. WITHDRAW (вывести) */
function Withdraw() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <SPButton variant="quiet" size="sm">Закрыть</SPButton>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Вывести из баланса</div>
          <div style={{ width: 60 }}/>
        </div>

        <div style={{ padding: "20px 20px 0" }}>
          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Доступно к выводу</div>
            <div style={{ font: "var(--sp-t-money-xl)", color: "#FFF", marginTop: 6, fontVariantNumeric: "tabular-nums" }}>840 <span style={{ font:"var(--sp-t-money-md)", color: "var(--sp-fg-3)" }}>₽</span></div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 6 }}>Минимальный остаток для активных будильников: 200 ₽</div>
          </SPCard>
        </div>

        <div style={{ padding: "20px 20px 0", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Сумма</div>
          <div style={{ display: "inline-flex", alignItems: "baseline", marginTop: 8 }}>
            <span style={{ font: "var(--sp-t-money-xl)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>640</span>
            <span style={{ font: "var(--sp-t-money-xl)", color: "var(--sp-fg-3)", marginLeft: 6 }}>₽</span>
          </div>
          <div style={{ display:"flex", justifyContent:"center", gap: 8, marginTop: 16 }}>
            <SPButton variant="quiet" size="sm">−100</SPButton>
            <SPButton variant="quiet" size="sm">+100</SPButton>
            <SPButton variant="quiet" size="sm">Всё</SPButton>
          </div>
        </div>

        <div style={{ padding: "24px 20px 0", flex: 1 }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 10 }}>Куда</div>
          <SPCard padding={4} radius={16}>
            <SPRow leading={<ApplePayMark/>}
              title="На карту в Apple Pay" subtitle="•••• 4827 · 2–3 рабочих дня" trailing={<IconCheck size={18} style={{ color: "var(--sp-money-400)" }}/>}/>
            <SPRow divider={false} leading={
              <div style={{ width: 40, height: 28, borderRadius: 6, background: "var(--sp-white-08)",
                display: "flex", alignItems: "center", justifyContent: "center", font: "10px/10px var(--sp-font-mono)", color: "var(--sp-fg-2)" }}>СБП</div>
            } title="По номеру телефона" subtitle="Мгновенно"/>
          </SPCard>
        </div>

        <div style={{ padding: "0 20px 32px" }}>
          <SPButton variant="money" size="lg" full>Вывести 640 ₽</SPButton>
        </div>
      </div>
    </div>
  );
}

/* Apple Pay logo mark — единая иконка для всех способов оплаты.
   Чёрный плашка-чип с глифом в стиле Apple Pay (упрощённый ⓅPay). */
function ApplePayMark() {
  return (
    <div style={{
      width: 40, height: 28, borderRadius: 6, background: "#000",
      display: "flex", alignItems: "center", justifyContent: "center",
      gap: 2, color: "#FFF",
    }}>
      <svg width="10" height="13" viewBox="0 0 18 22" fill="none" aria-hidden>
        <path d="M14.6 11.7c0-2 1.6-3 1.7-3-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.7-3.1.7-.7 0-1.7-.7-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.3 1 8.4.7 1 1.6 2.1 2.7 2 1.1 0 1.5-.7 2.7-.7 1.3 0 1.6.7 2.7.7 1.1 0 1.9-1 2.5-2 .8-1.1 1.1-2.2 1.2-2.3 0 0-2.3-.9-2.3-3.5zM12.7 5.5c.6-.7 1-1.7.9-2.7-.9 0-1.9.6-2.5 1.3-.5.6-1 1.6-.9 2.6 1 .1 1.9-.5 2.5-1.2z" fill="currentColor"/>
      </svg>
      <span style={{ font: "700 10px/10px var(--sp-font-body)", letterSpacing: "-.02em" }}>Pay</span>
    </div>
  );
}

/* 26. PAYMENT METHODS */
function PaymentMethods() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Способы оплаты</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "20px 20px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Hero: единственный способ оплаты — Apple Pay.
              Чёрная карточка а-ля iOS Wallet, без VISA/МИР визуалов. */}
          <div style={{ position: "relative", borderRadius: 20, padding: 22, height: 200,
            background: "linear-gradient(135deg, #15151A 0%, #0A0A0E 100%)",
            border: "1px solid rgba(255,255,255,.10)" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div className="sp-caps" style={{ color: "rgba(255,255,255,.5)" }}>По умолчанию</div>
              <div style={{ display: "flex", alignItems: "center", gap: 4, color: "#FFF" }}>
                <svg width="20" height="24" viewBox="0 0 18 22" fill="none" aria-hidden>
                  <path d="M14.6 11.7c0-2 1.6-3 1.7-3-1-1.4-2.5-1.6-3-1.6-1.3-.1-2.5.7-3.1.7-.7 0-1.7-.7-2.7-.7-1.4 0-2.7.8-3.4 2-1.5 2.5-.4 6.3 1 8.4.7 1 1.6 2.1 2.7 2 1.1 0 1.5-.7 2.7-.7 1.3 0 1.6.7 2.7.7 1.1 0 1.9-1 2.5-2 .8-1.1 1.1-2.2 1.2-2.3 0 0-2.3-.9-2.3-3.5zM12.7 5.5c.6-.7 1-1.7.9-2.7-.9 0-1.9.6-2.5 1.3-.5.6-1 1.6-.9 2.6 1 .1 1.9-.5 2.5-1.2z" fill="currentColor"/>
                </svg>
                <span style={{ font: "700 18px/22px var(--sp-font-body)", letterSpacing: "-.02em" }}>Pay</span>
              </div>
            </div>
            <div style={{ position: "absolute", left: 22, bottom: 22 }}>
              <div className="sp-caps" style={{ color: "rgba(255,255,255,.4)" }}>Привязанная карта</div>
              <div style={{ font: "20px/24px var(--sp-font-mono)", color: "#FFF", letterSpacing: ".1em", fontVariantNumeric: "tabular-nums", marginTop: 4 }}>
                •••• 4827
              </div>
              <div className="sp-meta" style={{ color: "rgba(255,255,255,.5)", marginTop: 6 }}>
                Управляется в приложении Wallet
              </div>
            </div>
          </div>

          {/* Альтернатива — СБП. Других карт нет: всё через Apple Pay/Wallet. */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Альтернатива</div>
            <SPCard padding={4} radius={16}>
              <SPRow divider={false} leading={
                <div style={{ width: 40, height: 28, borderRadius: 6, background: "var(--sp-white-08)",
                  display: "flex", alignItems: "center", justifyContent: "center", font: "10px/10px var(--sp-font-mono)", color: "var(--sp-fg-2)" }}>СБП</div>
              } title="Система быстрых платежей" subtitle="+7 ••• ••• 24 18 · для возвратов" trailing={<IconChevR size={16}/>}/>
            </SPCard>
          </div>

          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>Безопасность</div>
          <SPCard padding={20} radius={16}>
            <div style={{ display:"flex", gap: 12, alignItems:"flex-start" }}>
              <IconLock size={20} style={{ color: "var(--sp-money-400)", marginTop: 2 }}/>
              <div>
                <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>Только Apple Pay</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-2)", marginTop: 4 }}>
                  Мы не видим номер карты и не храним платёжные данные. Каждое списание подтверждается Face ID и проходит через Apple.
                </div>
              </div>
            </div>
          </SPCard>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { TxHistory, Deposit, Withdraw, PaymentMethods, ApplePayMark });
