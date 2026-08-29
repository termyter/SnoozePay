// SnoozePay — недостающие экраны для полного обзора.
// onboarding (3 шага), статистика, настройки, sound picker, empty states.

const { useState: oS } = React;

/* ============================================================
   ONBOARDING — 3 шага
   ============================================================ */
function Onboarding1() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <div style={{
        position: "absolute", left: "50%", top: 60, transform: "translateX(-50%)",
        width: 420, height: 420, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.25) 0%, transparent 60%)", filter: "blur(40px)",
      }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", padding: "54px 24px 32px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center" }}>
          <div style={{ fontSize: 96, lineHeight: 1, fontFamily: "var(--sp-font-mono)", color: "#FFF", letterSpacing: "-.05em", fontWeight: 200 }}>
            7:00
          </div>
          <div style={{
            marginTop: 20, padding: "8px 14px", borderRadius: 999,
            background: "var(--sp-grad-warn)", color: "var(--sp-fg-on-warn)",
            font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)",
            display: "inline-flex", boxShadow: "0 8px 24px rgba(245,158,11,.30)",
          }}>−50 ₽</div>
          <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 36, letterSpacing: "-.02em" }}>
            Будильник<br/>со ставкой
          </div>
          <div className="sp-body-lg" style={{ color: "var(--sp-fg-2)", marginTop: 14, maxWidth: 280 }}>
            Каждое откладывание стоит денег. Деньги не вернутся. Зато вы встанете.
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, marginBottom: 24 }}>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
        </div>
        <SPButton variant="money" size="lg" full>Дальше</SPButton>
      </div>
    </div>
  );
}

function Onboarding2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", padding: "54px 24px 32px" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>как это работает</div>
          <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 8, letterSpacing: "-.02em" }}>
            Положи баланс.<br/>Откладывай — теряй.
          </div>
          <div style={{ marginTop: 32, display: "flex", flexDirection: "column", gap: 14 }}>
            {[
              { n: "1", t: "Положили 500 ₽", s: "Это запас, из которого спишутся штрафы." },
              { n: "2", t: "Поспать ещё в 7:00 → −50 ₽", s: "Каждый раз когда вы тянете, деньги уходят." },
              { n: "3", t: "Встали с первого раза → ничего", s: "Баланс продолжает лежать. Готов к завтрашнему утру." },
            ].map((row, i) => (
              <div key={i} style={{ display: "flex", gap: 14, alignItems: "flex-start" }}>
                <div style={{
                  width: 32, height: 32, borderRadius: 10, flexShrink: 0,
                  background: "var(--sp-white-08)", color: "var(--sp-fg-2)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  font: "var(--sp-t-button-sm)", fontFamily: "var(--sp-font-mono)",
                }}>{row.n}</div>
                <div>
                  <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{row.t}</div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-2)", marginTop: 2 }}>{row.s}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, marginBottom: 24 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
        </div>
        <SPButton variant="money" size="lg" full>Дальше</SPButton>
      </div>
    </div>
  );
}

function Onboarding3() {
  const [v, setV] = oS(500);
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <div style={{
        position: "absolute", top: -120, left: -60,
        width: 320, height: 320, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.25) 0%, transparent 60%)", filter: "blur(40px)",
      }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, display: "flex", flexDirection: "column", padding: "54px 24px 32px" }}>
        <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>баланс · сколько положить</div>
        <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 8, letterSpacing: "-.02em" }}>
          Сколько ставите<br/>на свою дисциплину?
        </div>
        <div style={{ flex: 1, marginTop: 24, display: "flex", flexDirection: "column", gap: 8 }}>
          {[
            { v: 200, t: "Попробовать", s: "≈ 4 откладывания по 50 ₽" },
            { v: 500, t: "Серьёзно",     s: "≈ 10 откладываний · хватит на 2 недели", popular: true },
            { v: 1000, t: "Решительно",  s: "≈ 20 откладываний · спокойный месяц" },
          ].map(o => {
            const sel = v === o.v;
            return (
              <button key={o.v} onClick={()=>setV(o.v)} style={{
                width: "100%", padding: "16px 18px", borderRadius: 18, cursor: "pointer", textAlign: "left",
                background: sel ? "linear-gradient(135deg, rgba(46,219,159,.12), rgba(46,219,159,.04))" : "var(--sp-white-06)",
                border: sel ? "1px solid rgba(46,219,159,.40)" : "1px solid var(--sp-white-08)",
                color: "#FFF", display: "flex", alignItems: "center", justifyContent: "space-between",
                position: "relative", transition: "all 160ms var(--sp-ease-out)",
              }}>
                <div>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{o.t}</span>
                    {o.popular && <span style={{ font: "10px/12px var(--sp-font-body)", fontWeight: 700, color: "var(--sp-money-300)", letterSpacing: ".12em", textTransform: "uppercase" }}>популярно</span>}
                  </div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>{o.s}</div>
                </div>
                <div style={{ font: "var(--sp-t-money-md)", color: sel ? "var(--sp-money-300)" : "var(--sp-fg-1)", fontVariantNumeric: "tabular-nums" }}>
                  {o.v} ₽
                </div>
              </button>
            );
          })}
        </div>
        <div style={{ display: "flex", justifyContent: "center", gap: 6, margin: "16px 0 16px" }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: "var(--sp-white-12)" }}/>
          <span style={{ width: 24, height: 6, borderRadius: 3, background: "var(--sp-grad-money)" }}/>
        </div>
        <SPButton variant="money" size="lg" full icon={<IconShield size={18}/>} suffix={`${v} ₽`}>Положить</SPButton>
        <button style={{
          width: "100%", border: 0, background: "transparent", padding: "12px 0 0",
          font: "var(--sp-t-button-md)", color: "var(--sp-fg-3)", cursor: "pointer",
        }}>Позже — попробовать без баланса</button>
        <div className="sp-meta" style={{ textAlign: "center", color: "var(--sp-fg-4)", marginTop: 10 }}>
          Можно поменять в любой момент
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   STATISTICS
   ============================================================ */
function Statistics() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>

        <div style={{ padding: "8px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Апрель</div>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Статистика</div>
        </div>

        {/* Hero stats */}
        <div style={{ padding: "16px 20px 0", display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          <SPCard tone="raised" padding={16} radius={16}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Потери</div>
            <div style={{ font: "var(--sp-t-money-lg)", color: "var(--sp-pain-400)", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>−640 ₽</div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>за месяц</div>
          </SPCard>
          <SPCard tone="raised" padding={16} radius={16}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Лучшая серия</div>
            <div style={{ font: "var(--sp-t-money-lg)", color: "var(--sp-money-400)", marginTop: 4, fontVariantNumeric: "tabular-nums" }}>9 дн</div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>15–24 апр</div>
          </SPCard>
        </div>

        {/* Calendar heat */}
        <div style={{ padding: "20px 20px 0" }}>
          <div className="sp-caps" style={{ marginBottom: 10 }}>Календарь · красное = списание</div>
          <SPCard padding={16} radius={16}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 5 }}>
              {Array.from({ length: 28 }).map((_, i) => {
                const losses = [50,0,0,100,0,0,200,50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,50,100,0,40,0][i] || 0;
                const op = losses === 0 ? .14 : Math.min(.25 + losses/300, 1);
                return (
                  <div key={i} style={{
                    aspectRatio: "1 / 1", borderRadius: 8,
                    background: losses > 0
                      ? `linear-gradient(135deg, rgba(244,82,63,${op*0.9}), rgba(244,82,63,${op*0.5}))`
                      : "var(--sp-white-06)",
                    border: losses === 0 ? "1px solid var(--sp-white-08)" : "1px solid rgba(244,82,63,.20)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    fontFamily: "var(--sp-font-mono)", fontSize: 10, fontWeight: 600,
                    color: losses > 0 ? "#FFF" : "var(--sp-fg-4)",
                  }}>{i+1}</div>
                );
              })}
            </div>
          </SPCard>
        </div>

        {/* Chart bar */}
        <div style={{ padding: "20px 20px 0", flex: 1 }}>
          <div className="sp-caps" style={{ marginBottom: 10 }}>По дням недели · среднее</div>
          <SPCard padding={20} radius={16}>
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end" }}>
              {[
                {d:"Пн", v: 95},
                {d:"Вт", v: 60},
                {d:"Ср", v: 40},
                {d:"Чт", v: 35},
                {d:"Пт", v: 20},
                {d:"Сб", v: 5},
                {d:"Вс", v: 12},
              ].map(b => (
                <div key={b.d} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                  {/* Plot height belongs to the track, not the row — see #466. */}
                  <div style={{ width: "100%", height: 100, display: "flex", alignItems: "flex-end" }}>
                    <div style={{
                      width: "100%", height: `${b.v}%`, borderRadius: 6, minHeight: 4,
                      background: b.v > 60 ? "var(--sp-grad-pain)" : (b.v > 30 ? "var(--sp-grad-warn)" : "var(--sp-white-12)"),
                    }}/>
                  </div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontSize: 10 }}>{b.d}</div>
                </div>
              ))}
            </div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 12, paddingTop: 12, borderTop: "1px solid var(--sp-white-08)" }}>
              Понедельник — самый дорогой день. Положите больше баланса с воскресенья.
            </div>
          </SPCard>
        </div>

        <SPTabBar active="stats" />
      </div>
    </div>
  );
}

/* ============================================================
   SETTINGS
   ============================================================ */
function Settings() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0" }}>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Настройки</div>
        </div>

        <div style={{ padding: "20px 20px 0", display: "flex", flexDirection: "column", gap: 14, overflowY: "auto" }}>
          <div>
            <div className="sp-caps" style={{ marginBottom: 8, paddingLeft: 4 }}>баланс</div>
            <SPCard padding={4} radius={20}>
              <SPRow leading={<IconShield size={20} style={{color:"var(--sp-money-400)"}}/>} title="Текущий баланс" trailing={<span style={{font:"var(--sp-t-money-md)", color:"var(--sp-money-300)", fontVariantNumeric:"tabular-nums"}}>840 ₽</span>}/>
              <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Автопополнение" subtitle="Когда баланс < 200 ₽" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow divider={false} leading={<IconChart size={20} style={{color:"var(--sp-fg-3)"}}/>} title="История списаний" trailing={<IconChevR size={16}/>}/>
            </SPCard>
          </div>

          <div>
            <div className="sp-caps" style={{ marginBottom: 8, paddingLeft: 4 }}>будильники</div>
            <SPCard padding={4} radius={20}>
              <SPRow leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Звук по умолчанию" trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}/>
              <SPRow leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Громкость" subtitle="80% · растёт за 30 сек" trailing={<IconChevR size={16}/>}/>
              <SPRow divider={false} leading={<IconClock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Длина откладывания" trailing={<><span className="sp-meta">5 мин</span><IconChevR size={16}/></>}/>
            </SPCard>
          </div>

          <div>
            <div className="sp-caps" style={{ marginBottom: 8, paddingLeft: 4 }}>профиль</div>
            <SPCard padding={4} radius={20}>
              <SPRow divider={false} leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Уведомления" trailing={<IconChevR size={16}/>}/>
            </SPCard>
          </div>

          <div className="sp-meta" style={{ color: "var(--sp-fg-4)", textAlign: "center", marginTop: 8 }}>
            SnoozePay 1.0.0
          </div>
        </div>

        <SPTabBar active="settings" />
      </div>
    </div>
  );
}

/* ============================================================
   SOUND PICKER
   ============================================================ */
function SoundPicker() {
  const [sel, setSel] = oS("dawn");
  const sounds = [
    { id: "dawn", t: "Soft Dawn", s: "Тёплый рассвет с птицами" },
    { id: "energy", t: "Energy", s: "Бодрое пробуждение, нарастает" },
    { id: "birds", t: "Birds", s: "Только щебет, без музыки" },
    { id: "mountain", t: "Mountain", s: "Колокольчик и ветер" },
    { id: "classic", t: "Classic Beep", s: "Старый добрый писк" },
    { id: "custom", t: "Своя мелодия", s: "Из библиотеки" },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Звук</div>
          <SPButton variant="quiet" size="sm">Готово</SPButton>
        </div>

        <div style={{ padding: "20px 20px 0", flex: 1, overflowY: "auto" }}>
          <SPCard padding={4} radius={20}>
            {sounds.map((s, i) => {
              const isLast = i === sounds.length - 1;
              const on = sel === s.id;
              return (
                <button key={s.id} onClick={()=>setSel(s.id)} style={{
                  width: "100%", padding: "14px 16px", border: 0, background: "transparent",
                  textAlign: "left", cursor: "pointer", display: "flex", alignItems: "center", gap: 12,
                  borderBottom: !isLast ? "1px solid var(--sp-white-08)" : "0",
                }}>
                  <div style={{
                    width: 36, height: 36, borderRadius: 10,
                    background: on ? "var(--sp-grad-money)" : "var(--sp-white-06)",
                    display: "flex", alignItems: "center", justifyContent: "center",
                    color: on ? "var(--sp-fg-on-money)" : "var(--sp-fg-3)",
                  }}>
                    <IconSound size={18}/>
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{s.t}</div>
                    <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>{s.s}</div>
                  </div>
                  {on && (
                    <div style={{ color: "var(--sp-money-400)", display: "flex" }}>
                      <IconCheck size={20}/>
                    </div>
                  )}
                </button>
              );
            })}
          </SPCard>

          <div style={{ marginTop: 20 }}>
            <div className="sp-caps" style={{ marginBottom: 10 }}>Превью</div>
            <SPCard padding={20} radius={16}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <button style={{
                  width: 48, height: 48, borderRadius: 24, border: 0,
                  background: "var(--sp-grad-money)", color: "var(--sp-fg-on-money)",
                  display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
                  paddingLeft: 4,
                }}>
                  ▶
                </button>
                <div style={{ flex: 1 }}>
                  <div style={{ height: 3, background: "var(--sp-white-08)", borderRadius: 2, overflow: "hidden" }}>
                    <div style={{ height: "100%", width: "35%", background: "var(--sp-grad-money)" }}/>
                  </div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 6 }}>0:08 / 0:24</div>
                </div>
              </div>
            </SPCard>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   EMPTY STATES
   ============================================================ */
function EmptyAlarms() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0" }}>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Будильники</div>
        </div>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center", padding: "0 32px" }}>
          <div style={{
            width: 84, height: 84, borderRadius: 24,
            background: "var(--sp-white-06)", display: "flex", alignItems: "center", justifyContent: "center",
            border: "1px solid var(--sp-white-08)",
          }}>
            <IconBell size={40} style={{ color: "var(--sp-fg-3)" }}/>
          </div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 20, letterSpacing: "-.01em" }}>
            Ни одного будильника
          </div>
          <div className="sp-body-lg" style={{ color: "var(--sp-fg-2)", marginTop: 10, maxWidth: 280 }}>
            Создайте первый — выставите время, цену откладывания и положите баланс.
          </div>
          <div style={{ marginTop: 28 }}>
            <SPButton variant="money" size="lg" icon={<IconPlus size={18}/>}>Создать будильник</SPButton>
          </div>
        </div>
        <SPTabBar active="alarms"/>
      </div>
    </div>
  );
}

function EmptyStats() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Апрель</div>
          <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Статистика</div>
        </div>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", textAlign: "center", padding: "0 32px" }}>
          <div style={{
            width: 84, height: 84, borderRadius: 24,
            background: "linear-gradient(135deg, rgba(46,219,159,.16), rgba(46,219,159,.04))",
            border: "1px solid rgba(46,219,159,.25)",
            display: "flex", alignItems: "center", justifyContent: "center",
          }}>
            <IconChart size={40} style={{ color: "var(--sp-money-400)" }}/>
          </div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 20, letterSpacing: "-.01em" }}>
            Пока нечего считать
          </div>
          <div className="sp-body-lg" style={{ color: "var(--sp-fg-2)", marginTop: 10, maxWidth: 280 }}>
            Статистика появится после первой недели использования.
          </div>
          <div style={{ marginTop: 24, padding: "10px 14px", borderRadius: 999, background: "rgba(46,219,159,.10)", border: "1px solid rgba(46,219,159,.20)", display: "inline-flex", alignItems: "center", gap: 8 }}>
            <IconFlame size={14} style={{ color: "var(--sp-money-400)" }}/>
            <span className="sp-meta" style={{ color: "var(--sp-money-300)" }}>Стрик · 2 дня</span>
          </div>
        </div>
        <SPTabBar active="stats"/>
      </div>
    </div>
  );
}

Object.assign(window, {
  Onboarding1, Onboarding2, Onboarding3,
  Statistics, Settings, SoundPicker,
  EmptyAlarms, EmptyStats,
});
