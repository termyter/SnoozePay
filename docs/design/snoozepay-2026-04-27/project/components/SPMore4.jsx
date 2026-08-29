// SnoozePay — экраны 27-30: статистика, настройки, рефералы, выключение будильника

const { useState: oS4 } = React;

/* 27. STATS */
function Stats() {
  const days = [
    { l: "Пн", saved: 100, lost: 50 },
    { l: "Вт", saved: 150, lost: 0 },
    { l: "Ср", saved: 0, lost: 350 }, // плохой день
    { l: "Чт", saved: 150, lost: 0 },
    { l: "Пт", saved: 100, lost: 50 },
    { l: "Сб", saved: 150, lost: 0 },
    { l: "Вс", saved: 150, lost: 0 },
  ];
  const max = 350;
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Статистика</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "16px 20px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 12 }}>
          {/* Hero — серия */}
          <SPCard padding={24} radius={24}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>Серия</div>
                <div style={{ display: "flex", alignItems: "baseline", marginTop: 6 }}>
                  <span style={{ font: "var(--sp-t-money-xl)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>23</span>
                  <span style={{ font: "var(--sp-t-h3)", color: "var(--sp-fg-3)", marginLeft: 6 }}>дня</span>
                </div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>Последний срыв: 8 января</div>
              </div>
              <div style={{ width: 56, height: 56, borderRadius: 18, background: "var(--sp-grad-warn)",
                display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 8px 24px rgba(245,158,11,.30)" }}>
                <IconFlame size={28} style={{ color: "var(--sp-fg-on-warn)" }}/>
              </div>
            </div>

            {/* heat map — последние 49 дней */}
            <div style={{ marginTop: 20, display: "grid", gridTemplateColumns: "repeat(14, 1fr)", gap: 4 }}>
              {Array.from({length: 42}).map((_,i) => {
                const v = [0,2,1,2,3,2,1,0,2,3,2,1,0,1, 2,1,2,0,1,2,3, 2,1,2,3,2,1,0,2,3,2,1,3,2, 2,3,2,3,3,2,2,3][i];
                const colors = ["var(--sp-white-06)", "rgba(245,158,11,.25)", "rgba(245,158,11,.5)", "var(--sp-warn-400)"];
                return <div key={i} style={{ aspectRatio: "1/1", borderRadius: 4, background: colors[v] }}/>;
              })}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
              <span className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>6 недель назад</span>
              <span className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>сегодня</span>
            </div>
          </SPCard>

          {/* Эта неделя — bar chart */}
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <div className="sp-caps">Эта неделя</div>
              <span className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>зелёное — сэкономлено · красное — потеряно</span>
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end", height: 120, marginTop: 16 }}>
              {days.map((d, i) => (
                <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                  <div style={{ flex: 1, width: "100%", display: "flex", flexDirection: "column", justifyContent: "flex-end", gap: 2 }}>
                    {d.lost > 0 && (
                      <div style={{ width: "100%", height: `${(d.lost/max)*100}%`, borderRadius: "6px 6px 2px 2px", background: "var(--sp-grad-pain)" }}/>
                    )}
                    {d.saved > 0 && (
                      <div style={{ width: "100%", height: `${(d.saved/max)*100}%`, borderRadius: d.lost ? "2px 2px 6px 6px" : 6, background: "var(--sp-grad-money)" }}/>
                    )}
                  </div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontSize: 10 }}>{d.l}</div>
                </div>
              ))}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 16, paddingTop: 16, borderTop: "1px solid var(--sp-white-06)" }}>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Сэкономили</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-money-400)", fontVariantNumeric: "tabular-nums" }}>+800 ₽</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Потратили</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-pain-400)", fontVariantNumeric: "tabular-nums" }}>−400 ₽</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Чистый</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>+400 ₽</div>
              </div>
            </div>
          </SPCard>

          {/* Среднее время подъёма */}
          <SPCard padding={20} radius={20}>
            <div className="sp-caps">Время подъёма</div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 8 }}>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>В среднем</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "#FFF", fontFamily: "var(--sp-font-mono)", fontVariantNumeric: "tabular-nums" }}>7:04</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Раньше было</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)", textDecoration: "line-through", fontVariantNumeric: "tabular-nums" }}>7:38</div>
              </div>
              <div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Раньше на</div>
                <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-money-400)", fontVariantNumeric: "tabular-nums" }}>34 мин</div>
              </div>
            </div>
          </SPCard>
        </div>
      </div>
    </div>
  );
}

/* 28. SETTINGS */
function SettingsV2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Настройки</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "20px 20px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Профиль-карточки нет: аккаунта в MVP нет (#237). Экран открывается
              сразу секцией «Финансы». */}

          {/* Section: финансы */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Финансы</div>
            <SPCard padding={4} radius={16}>
              {/* «Способы оплаты» убраны: оплата идёт через StoreKit, отдельного
                  экрана карт в MVP нет (#237, подтверждено #521). */}
              <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-warn-400)"}}/>} title="Цена откладывания по умолчанию" trailing={<><span style={{font:"var(--sp-t-money-md)", color: "var(--sp-warn-400)"}}>50 ₽</span><IconChevR size={16}/></>}/>
              <SPRow divider={false} leading={<IconClock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Длительность откладывания" trailing={<><span className="sp-meta">9 мин</span><IconChevR size={16}/></>}/>
            </SPCard>
          </div>

          {/* Section: уведомления и звук */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Звук и уведомления</div>
            <SPCard padding={4} radius={16}>
              <SPRow leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Громкость" trailing={<><span className="sp-meta">80%</span><IconChevR size={16}/></>}/>
              <SPRow leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Critical Alerts" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow divider={false} leading={<IconClock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Вибрация" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            </SPCard>
          </div>

          {/* Section: правила */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Правила</div>
            <SPCard padding={4} radius={16}>
              <SPRow leading={<IconFlame size={20} style={{color:"var(--sp-pain-400)"}}/>} title="Прогрессивная цена" subtitle="50 → 100 → 200 → 400" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-money-400)"}}/>} title="Бонус за серию" subtitle="+10% к балансу за 7 дней" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow divider={false} leading={<IconLock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Защита от скуки" subtitle="Не давать выключить во время звонка" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            </SPCard>
          </div>

          {/* Section: пригласить друга — отдельный блок с двумя действиями.
              Свой код — копируется. Поле «Код друга» — ввод чужого кода прямо здесь,
              чтобы не идти на отдельный экран. Дублирует функционал экрана «Пригласить». */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Пригласить друга</div>
            <SPCard padding={16} radius={16}>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Ваш код · поделиться, чтобы получить +200 ₽</div>
              <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 8 }}>
                <div style={{ flex: 1, font: "18px/22px var(--sp-font-mono)", color: "#FFF", letterSpacing: ".15em" }}>WAKEUP-7K2</div>
                <SPButton variant="money" size="sm">Копировать</SPButton>
              </div>
              <div style={{ height: 1, background: "var(--sp-white-08)", margin: "16px 0" }}/>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Код друга · ввести один раз</div>
              <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 8 }}>
                <input
                  placeholder="WAKEUP-•••"
                  style={{
                    flex: 1, border: 0, outline: "none", background: "var(--sp-white-06)",
                    color: "#FFF", caretColor: "var(--sp-money-400)",
                    font: "16px/22px var(--sp-font-mono)", letterSpacing: ".1em",
                    padding: "10px 12px", borderRadius: 10,
                  }}
                />
                <SPButton variant="quiet" size="sm">Применить</SPButton>
              </div>
            </SPCard>
          </div>

          {/* Section: остальное. Строки «Выйти из аккаунта» нет — аккаунта в MVP
              нет (#237). Тема приложения живёт здесь же сегментом (#283). */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 4px 8px" }}>Прочее</div>
            <SPCard padding={4} radius={16}>
              <SPRow leading={<IconLock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Политика конфиденциальности" trailing={<IconChevR size={16}/>}/>
              <SPRow leading={<IconLock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Пользовательское соглашение" trailing={<IconChevR size={16}/>}/>
              <SPRow leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Связаться с нами" subtitle="support@snoozepay.app" trailing={<IconChevR size={16}/>}/>
              <div style={{ padding: "4px 20px 12px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "8px 0" }}>
                  <IconMoon size={20} style={{color:"var(--sp-fg-3)"}}/>
                  <span style={{ font: "var(--sp-t-h4)", color: "var(--sp-fg-1)" }}>Тема</span>
                </div>
                <SPSegmented
                  options={[{value:"system",label:"Системная"},{value:"light",label:"Светлая"},{value:"dark",label:"Тёмная"}]}
                  value="system" onChange={()=>{}}
                />
              </div>
            </SPCard>
          </div>

          <div className="sp-meta" style={{ color: "var(--sp-fg-3)", textAlign: "center", padding: "8px 0 16px" }}>
            SnoozePay 1.0.0 · build 142
          </div>
        </div>
      </div>
    </div>
  );
}

/* 29. REFERRAL */
function Referral() {
  const [friendCode, setFriendCode] = oS4("");
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Пригласить</div>
          <div style={{ width: 36 }}/>
        </div>

        {/* Hero */}
        <div style={{ padding: "16px 20px 0" }}>
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
        </div>

        {/* Свой код */}
        <div style={{ padding: "20px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Ваш код</div>
          <SPCard padding={16} radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ flex: 1, font: "20px/24px var(--sp-font-mono)", color: "#FFF", letterSpacing: ".15em" }}>WAKEUP-7K2</div>
              <SPButton variant="money" size="sm">Копировать</SPButton>
            </div>
          </SPCard>
        </div>

        {/* Ввод кода друга — у нового юзера так начисляется бонус другу.
            Плоский input + CTA «Применить»; разрешено ввести один раз. */}
        <div style={{ padding: "20px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Код друга</div>
          <SPCard padding={12} radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <input
                value={friendCode}
                onChange={(e)=>setFriendCode(e.target.value.toUpperCase())}
                placeholder="Например, WAKEUP-7K2"
                style={{
                  flex: 1, border: 0, outline: "none", background: "transparent",
                  color: "#FFF", caretColor: "var(--sp-money-400)",
                  font: "16px/22px var(--sp-font-mono)", letterSpacing: ".1em",
                  padding: "8px 4px",
                }}
              />
              <SPButton variant={friendCode ? "money" : "quiet"} size="sm" disabled={!friendCode}>Применить</SPButton>
            </div>
          </SPCard>
          <div className="sp-meta" style={{ color: "var(--sp-fg-4)", marginTop: 6, padding: "0 4px" }}>
            Можно ввести один раз. Бонус начисляется обоим, когда вы продержитесь 7 дней.
          </div>
        </div>

        {/* Прогресс */}
        <div style={{ padding: "20px 20px 0", flex: 1, overflowY: "auto" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 10 }}>Друзья</div>
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

        <div style={{ padding: "16px 20px 32px", display: "flex", flexDirection: "column", gap: 8 }}>
          <SPButton variant="money" size="lg" full>Поделиться кодом</SPButton>
        </div>
      </div>
    </div>
  );
}

/* 30. ALARM OFF / DISABLE WARNING (после 3 срывов подряд) */
function AlarmOffWarning() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "var(--sp-bg-0)" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, padding: "54px 24px 32px", height: "100%", display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <SPButton variant="quiet" size="sm">Закрыть</SPButton>
          <div className="sp-caps" style={{ color: "var(--sp-pain-400)" }}>Внимание</div>
          <div style={{ width: 60 }}/>
        </div>

        <div style={{ marginTop: 20 }}>
          <div style={{ width: 80, height: 80, borderRadius: 24, background: "var(--sp-grad-pain)",
            display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 16px 48px rgba(244,82,63,.40)" }}>
            <IconFlame size={40} style={{ color: "var(--sp-fg-on-pain)" }}/>
          </div>
          <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 20, letterSpacing: "-.02em" }}>
            Вы поспал ещёи 3 раза подряд
          </div>
          <div className="sp-body-lg" style={{ color: "var(--sp-fg-2)", marginTop: 12 }}>
            За эту неделю списано <span style={{ color: "var(--sp-pain-400)", fontFamily: "var(--sp-font-mono)" }}>−750 ₽</span>.
            Возможно, что-то пошло не так. Что хотите сделать?
          </div>
        </div>

        <div style={{ marginTop: 24, display: "flex", flexDirection: "column", gap: 10 }}>
          <SPCard padding={16} radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 40, height: 40, borderRadius: 12, background: "rgba(255,255,255,.06)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                <IconClock size={20} style={{ color: "var(--sp-fg-2)" }}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>Перенести будильник</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Сегодня поздно лёг — встаём в 8:00</div>
              </div>
              <IconChevR size={16}/>
            </div>
          </SPCard>
          <SPCard padding={16} radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 40, height: 40, borderRadius: 12, background: "rgba(245,158,11,.14)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                <IconCoin size={20} style={{ color: "var(--sp-warn-400)" }}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>Снизить цену откладывания</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Сейчас 50 ₽ → попробовать 20 ₽</div>
              </div>
              <IconChevR size={16}/>
            </div>
          </SPCard>
          <SPCard padding={16} radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div style={{ width: 40, height: 40, borderRadius: 12, background: "rgba(244,82,63,.14)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                <IconClose size={20} style={{ color: "var(--sp-pain-400)" }}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>Выключить SnoozePay</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Будильник останется обычным</div>
              </div>
              <IconChevR size={16}/>
            </div>
          </SPCard>
        </div>

        <div style={{ flex: 1 }}/>
        <SPButton variant="ghost" size="md" full>Всё в порядке, продолжаем</SPButton>
      </div>
    </div>
  );
}

Object.assign(window, { Stats, SettingsV2, Referral, AlarmOffWarning });
