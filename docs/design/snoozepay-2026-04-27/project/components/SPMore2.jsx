// SnoozePay — экраны 16-22: запуск, разрешения, детали/редакт., модалки, картинки, звук-настройки

const { useState: oS2 } = React;

/* 16. SPLASH */
function Splash() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#0E1320" }}>
      <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)",
        width: 480, height: 480, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.30) 0%, transparent 60%)", filter: "blur(40px)" }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", gap: 20 }}>
        <div style={{ width: 96, height: 96, borderRadius: 28, background: "var(--sp-grad-warn)",
          display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 16px 48px rgba(245,158,11,.40)" }}>
          <IconBell size={48} style={{ color: "var(--sp-fg-on-warn)" }}/>
        </div>
        <div style={{ font: "var(--sp-t-h1)", color: "#FFF", letterSpacing: "-.02em" }}>SnoozePay</div>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Будильник со ставкой</div>
      </div>
    </div>
  );
}

/* 17. PERMISSIONS */
function Permissions() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, paddingTop: 54, padding: "54px 24px 32px", display: "flex", flexDirection: "column" }}>
        <div className="sp-caps" style={{ color: "var(--sp-warn-300)" }}>последний шаг</div>
        <div style={{ font: "var(--sp-t-h1)", color: "#FFF", marginTop: 8, letterSpacing: "-.02em" }}>
          Чтобы будильник работал
        </div>
        <div className="sp-body-lg" style={{ color: "var(--sp-fg-2)", marginTop: 12, maxWidth: 320 }}>
          Без этих разрешений iOS не разбудит вас в нужное время — даже если телефон беззвучный.
        </div>
        <div style={{ marginTop: 28, display: "flex", flexDirection: "column", gap: 12, flex: 1 }}>
          {[
            { i: <IconBell size={20}/>, t: "Уведомления", s: "Чтобы показать будильник на экране", on: true },
            { i: <IconSound size={20}/>, t: "Critical Alerts", s: "Чтобы звук прошёл через беззвучный режим", on: true },
            { i: <IconClock size={20}/>, t: "Фоновый режим", s: "Чтобы таймеры не убивались системой", on: false },
          ].map((r, i) => (
            <SPCard key={i} padding={16} radius={16}>
              <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                <div style={{ width: 40, height: 40, borderRadius: 12, background: r.on ? "var(--sp-grad-money)" : "var(--sp-white-08)",
                  color: r.on ? "var(--sp-fg-on-money)" : "var(--sp-fg-3)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                  {r.i}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{r.t}</div>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>{r.s}</div>
                </div>
                {r.on
                  ? <IconCheck size={20} style={{ color: "var(--sp-money-400)" }}/>
                  : <span className="sp-caps" style={{ color: "var(--sp-warn-400)" }}>Дать</span>}
              </div>
            </SPCard>
          ))}
        </div>
        <SPButton variant="money" size="lg" full>Готово</SPButton>
      </div>
    </div>
  );
}

/* 18. ALARM DETAIL */
function AlarmDetail() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Будильник</div>
          <SPButton variant="quiet" size="sm">Изменить</SPButton>
        </div>

        {/* hero — image bg + время */}
        <div style={{ padding: "16px 20px 0" }}>
          <div style={{ position: "relative", borderRadius: 24, overflow: "hidden", height: 200,
            background: "linear-gradient(135deg, #2B1A0E 0%, #6B3517 50%, #C46A1A 100%)" }}>
            <div style={{ position: "absolute", left: "50%", bottom: -40, transform: "translateX(-50%)",
              width: 240, height: 240, borderRadius: "50%",
              background: "radial-gradient(circle, rgba(255,184,77,.55) 0%, transparent 60%)", filter: "blur(20px)" }}/>
            <div style={{ position: "absolute", inset: 0, padding: 20, display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
              <div className="sp-caps" style={{ color: "rgba(255,255,255,.7)" }}>Будни · Пн–Пт</div>
              <div>
                <div style={{ font: "200 72px/72px var(--sp-font-mono)", color: "#FFF", letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums" }}>7:00</div>
                <div className="sp-meta" style={{ color: "rgba(255,255,255,.7)", marginTop: 4 }}>До звонка ~21 час</div>
              </div>
            </div>
          </div>
        </div>

        <div style={{ padding: "20px 20px 0", display: "flex", flexDirection: "column", gap: 12, flex: 1, overflowY: "auto" }}>
          <SPCard padding={4} radius={20}>
            <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-warn-400)"}}/>} title="Цена откладывания" trailing={<span style={{font:"var(--sp-t-money-md)", color:"var(--sp-warn-400)"}}>50 ₽</span>}/>
            <SPRow leading={<IconFlame size={20} style={{color:"var(--sp-pain-400)"}}/>} title="Прогрессив" subtitle="50 → 100 → 200 → 400" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            <SPRow leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Звук" trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}/>
            <SPRow divider={false} leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Тема" trailing={<><span className="sp-meta">Dawn</span><IconChevR size={16}/></>}/>
          </SPCard>

          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 10 }}>Последняя неделя</div>
            <div style={{ display: "flex", gap: 6, alignItems: "flex-end", height: 50 }}>
              {[0,50,0,100,0,0,0].map((v,i)=>(
                <div key={i} style={{ flex:1, display:"flex", flexDirection:"column", alignItems:"center", gap:4 }}>
                  <div style={{ width:"100%", height: v?`${v}%`:4, minHeight:4, borderRadius:4, background: v?"var(--sp-grad-pain)":"var(--sp-white-08)" }}/>
                  <div className="sp-meta" style={{ color: "var(--sp-fg-4)", fontSize: 10 }}>{["П","В","С","Ч","П","С","В"][i]}</div>
                </div>
              ))}
            </div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 10 }}>
              Списано за неделю: <span style={{ fontFamily: "var(--sp-font-mono)", color: "var(--sp-pain-400)" }}>−150 ₽</span>
            </div>
          </SPCard>
        </div>
      </div>
    </div>
  );
}

/* 19. ALARM EDIT — единый экран редактирования (без отдельного «детали»).
   Сверху, как в iOS Reminders, поле «Название», под ним время; в карточке — длительность снуза (ползунок 1–15 мин). */
function AlarmEdit() {
  const [name, setName] = oS2("Будни");
  const [snoozeMin, setSnoozeMin] = oS2(9);
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <SPButton variant="quiet" size="sm">Отмена</SPButton>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Будильник</div>
          <SPButton variant="money" size="sm">Сохранить</SPButton>
        </div>

        {/* Name input — iOS Reminders style: огромный текст, без рамки, с подчёркиванием */}
        <div style={{ padding: "12px 20px 0" }}>
          <input
            value={name}
            onChange={(e)=>setName(e.target.value)}
            placeholder="Название"
            style={{
              width: "100%", border: 0, outline: "none", background: "transparent",
              color: "var(--sp-fg-1)", caretColor: "var(--sp-warn-400)",
              font: "var(--sp-t-h1)", letterSpacing: "-.02em",
              padding: "8px 0 12px",
              borderBottom: "1px solid var(--sp-white-08)",
            }}
          />
        </div>

        {/* Time */}
        <div style={{ padding: "20px 20px 0", textAlign: "center" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 6 }}>Подъём</div>
          <div style={{ display: "inline-flex", alignItems: "baseline" }}>
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
        </div>

        <div style={{ padding: "24px 20px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 12 }}>
          {/* Длительность снуза — ползунок 1..15 мин */}
          <SPCard padding={20} radius={20}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 12 }}>
              <div>
                <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Длительность откладывания</div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>На сколько минут отодвигается звонок</div>
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
            <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-warn-400)"}}/>} title="Цена откладывания" trailing={<><span style={{font:"var(--sp-t-money-md)", color:"var(--sp-warn-400)"}}>50 ₽</span><IconChevR size={16}/></>}/>
            <SPRow leading={<IconFlame size={20} style={{color:"var(--sp-pain-400)"}}/>} title="Прогрессив" subtitle="50 → 100 → 200 → 400" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            <SPRow leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Звук" trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}/>
            <SPRow divider={false} leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Тема" trailing={<><span className="sp-meta">Dawn</span><IconChevR size={16}/></>}/>
          </SPCard>
          <SPButton variant="pain" size="lg" full>Удалить будильник</SPButton>
          <div style={{ height: 16 }}/>
        </div>
      </div>
    </div>
  );
}

/* 20. CONFIRM DELETE */
function ConfirmDelete() {
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>
      <div style={{ position:"absolute", inset:0, background:"rgba(6,9,18,.85)", backdropFilter:"blur(8px)" }}/>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ position: "absolute", inset: 0, display: "flex", justifyContent: "center", alignItems: "flex-end", padding: "0 12px 16px" }}>
        <div style={{ width:"100%", background: "var(--sp-bg-2)", borderRadius: 24, padding: 24, textAlign: "center", border: "1px solid var(--sp-white-08)" }}>
          <div style={{ width: 64, height: 64, borderRadius: 20, background: "rgba(244,82,63,.14)", border: "1px solid rgba(244,82,63,.30)",
            margin: "0 auto", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <IconClose size={28} style={{ color: "var(--sp-pain-400)" }}/>
          </div>
          <div style={{ font: "var(--sp-t-h2)", color: "#FFF", marginTop: 16, letterSpacing: "-.01em" }}>Удалить будильник?</div>
          <div className="sp-body" style={{ color: "var(--sp-fg-2)", marginTop: 8 }}>
            Будни · Пн–Пт · 7:00. Баланс 840 ₽ останется на месте — он привязан к аккаунту, а не к будильнику.
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 20 }}>
            <SPButton variant="pain" size="lg" full>Удалить</SPButton>
            <SPButton variant="quiet" size="md" full>Отмена</SPButton>
          </div>
        </div>
      </div>
    </div>
  );
}

/* 21. THEME PICKER (картинка для будильника) */
function ThemePicker() {
  const [sel, setSel] = oS2("dawn");
  const themes = [
    { id: "dawn",     t: "Рассвет",  s: "Тёплый янтарь",  bg: "linear-gradient(135deg, #2B1A0E 0%, #6B3517 50%, #C46A1A 100%)" },
    { id: "ocean",    t: "Океан",    s: "Холодный мятный",bg: "linear-gradient(135deg, #08182A 0%, #134E5E 50%, #71B280 100%)" },
    { id: "mountain", t: "Горы",     s: "Молочный свет",  bg: "linear-gradient(135deg, #1A1F2E 0%, #5A6B8A 50%, #E1E5EA 100%)" },
    { id: "forest",   t: "Лес",      s: "Хвойный сумрак", bg: "linear-gradient(135deg, #0A1A0A 0%, #1E3823 50%, #4A6B3A 100%)" },
    { id: "neon",     t: "Неон",     s: "Городская ночь", bg: "linear-gradient(135deg, #0A0A1F 0%, #3D1E63 50%, #FF3D8A 100%)" },
    { id: "abstract", t: "Абстракт", s: "Чистый цвет",    bg: "linear-gradient(135deg, #1E1E1E 0%, #2A2A2A 100%)" },
    { id: "custom",   t: "Своё фото",s: "Из галереи",     bg: "transparent", custom: true },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Тема будильника</div>
          <SPButton variant="quiet" size="sm">Готово</SPButton>
        </div>

        {/* Preview */}
        <div style={{ padding: "16px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Превью firing-screen</div>
          <div style={{ position: "relative", borderRadius: 20, overflow: "hidden", height: 180,
            background: themes.find(t=>t.id===sel).bg }}>
            <div style={{ position: "absolute", left: "50%", bottom: -40, transform: "translateX(-50%)",
              width: 240, height: 240, borderRadius: "50%",
              background: "radial-gradient(circle, rgba(255,184,77,.40) 0%, transparent 60%)", filter: "blur(20px)" }}/>
            <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <span style={{ font: "200 56px/56px var(--sp-font-mono)", color: "#FFF", letterSpacing: "-.04em", fontVariantNumeric: "tabular-nums" }}>7:00</span>
            </div>
          </div>
        </div>

        <div style={{ padding: "20px 20px 0", flex: 1, overflowY: "auto" }}>
          <div className="sp-caps" style={{ marginBottom: 10 }}>Готовые темы</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 10 }}>
            {themes.map(th => {
              const on = sel === th.id;
              return (
                <button key={th.id} onClick={()=>setSel(th.id)} style={{
                  position: "relative", border: 0, padding: 0, cursor: "pointer",
                  borderRadius: 16, overflow: "hidden", aspectRatio: "1/1.2",
                  background: th.custom ? "var(--sp-white-06)" : th.bg,
                  outline: on ? "2px solid var(--sp-money-400)" : "1px solid var(--sp-white-08)",
                  outlineOffset: on ? "2px" : "0",
                }}>
                  {th.custom && (
                    <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <IconPlus size={28} style={{ color: "var(--sp-fg-3)" }}/>
                    </div>
                  )}
                  <div style={{ position: "absolute", left: 8, right: 8, bottom: 8 }}>
                    <div style={{ font: "var(--sp-t-button-sm)", color: "#FFF", textShadow: "0 1px 4px rgba(0,0,0,.6)", textAlign: "left" }}>{th.t}</div>
                    <div style={{ font: "10px/12px var(--sp-font-body)", color: "rgba(255,255,255,.75)", textShadow: "0 1px 4px rgba(0,0,0,.6)", textAlign: "left", marginTop: 1 }}>{th.s}</div>
                  </div>
                  {on && (
                    <div style={{ position: "absolute", top: 6, right: 6, width: 22, height: 22, borderRadius: 11,
                      background: "var(--sp-grad-money)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <IconCheck size={14} style={{ color: "var(--sp-fg-on-money)" }}/>
                    </div>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

/* 22. VOLUME SETTING */
function VolumeSetting() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ paddingTop: 54, flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "8px 20px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Громкость</div>
          <div style={{ width: 36 }}/>
        </div>
        <div style={{ padding: "32px 20px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Текущий уровень</div>
          <div style={{ font: "var(--sp-t-money-xl)", color: "#FFF", marginTop: 8, fontVariantNumeric: "tabular-nums" }}>80<span style={{ fontSize: 32, opacity: .5 }}>%</span></div>
        </div>
        <div style={{ padding: "24px 20px 0" }}>
          <div style={{ position: "relative", height: 8, borderRadius: 4, background: "var(--sp-white-08)" }}>
            <div style={{ position: "absolute", left: 0, top: 0, height: "100%", width: "80%", borderRadius: 4, background: "var(--sp-grad-money)" }}/>
            <div style={{ position: "absolute", left: "80%", top: "50%", transform: "translate(-50%,-50%)",
              width: 28, height: 28, borderRadius: 14, background: "#FFF", boxShadow: "0 4px 16px rgba(0,0,0,.4)" }}/>
          </div>
        </div>
        <div style={{ padding: "32px 20px 0", flex: 1 }}>
          <SPCard padding={4} radius={20}>
            <SPRow leading={<IconClock size={20} style={{ color: "var(--sp-fg-3)" }}/>} title="Нарастает за 30 сек" subtitle="Начинает тихо и доходит до уровня" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            <SPRow divider={false} leading={<IconBell size={20} style={{ color: "var(--sp-fg-3)" }}/>} title="Игнорировать беззвучный режим" subtitle="Critical Alerts" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
          </SPCard>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Splash, Permissions, AlarmDetail, AlarmEdit, ConfirmDelete, ThemePicker, VolumeSetting });
