// SnoozePay — экраны 27-30: статистика, настройки, рефералы, выключение будильника

const { useState: oS4 } = React;

/* 27. STATS — top-level tab. Без кнопки "Назад" (это не дочерний экран,
   а основной таб). Внизу — общий SPTabBar с active="stats".
   Три блока: серия + поведенческие графики (без денег и времени подъёма).
   Props:
     tappedCell : { row, col, date, weekday, snoozes, spent, status } | null
                  — для фрейма 27a: имитирует тап по ячейке heatmap'а,
                  показывает выделение и тултип со статусом дня. */
function Stats({ tappedCell = null } = {}) {
  /* Откладывания по дням недели — среднее за последние 4 недели.
     Худший день — среда (7 раз). Остальные дни — приглушённый бар. */
  const byWeekday = [
    { l: "Пн", n: 4 },
    { l: "Вт", n: 2 },
    { l: "Ср", n: 7 },
    { l: "Чт", n: 3 },
    { l: "Пт", n: 5 },
    { l: "Сб", n: 1 },
    { l: "Вс", n: 0 },
  ];
  const wdMax = Math.max(...byWeekday.map(d => d.n));
  const worstIdx = byWeekday.reduce((a, d, i) => d.n > byWeekday[a].n ? i : a, 0);
  const worstDayFull = ["понедельник","вторник","среда","четверг","пятница","суббота","воскресенье"][worstIdx];

  /* Откладывания по неделям — последние 8, включая текущую.
     Тренд явно падает — это значит, пользователь срывается реже. */
  const weeks = [
    { wk: "−7", n: 22 },
    { wk: "−6", n: 18 },
    { wk: "−5", n: 16 },
    { wk: "−4", n: 14 },
    { wk: "−3", n: 12 },
    { wk: "−2", n: 9 },
    { wk: "−1", n: 7 },
    { wk: "0",  n: 5, current: true },
  ];
  const wMax = Math.max(...weeks.map(w => w.n));
  const thisWk = weeks[weeks.length - 1].n;
  const prevWk = weeks[weeks.length - 2].n;
  const diff = thisWk - prevWk; // <0 = меньше срывов = лучше
  const trendBetter = diff < 0;
  const trendSame   = diff === 0;
  const trendColor  = trendBetter ? "var(--sp-money-400)" : trendSame ? "var(--sp-fg-2)" : "var(--sp-pain-400)";
  const trendHeadline = trendBetter ? "Становится лучше" : trendSame ? "Стабильно" : "Чаще, чем неделю назад";

  /* Heatmap серии — calendar view текущего месяца (январь 2026, 5 недель).
     Сегодня = 27 января (Вт, row 4 col 1). Дни до сегодня — заполнены
     данными; после — пустые ('-'). Дни вне месяца тоже '-'.
     Семантика клеток:
       'g' — 0 откладываний (встал сразу)  → money-gradient
       'y' — 1–2 откладывания              → warn-gradient
       'r' — 3+ откладываний               → pain-gradient
       '-' — будильника не было / вне месяца / будущее → почти-чёрная клетка
     Подписи дат и легенда убраны — карта читается как обычный календарь. */
  const heatmapRows = [
    /* Wk Dec29–Jan4 */    "---ggrr",
    /* Wk Jan5–11    */    "ryygy--",
    /* Wk Jan12–18   */    "ygggy--",
    /* Wk Jan19–25   */    "ggyrg--",
    /* Wk Jan26–Feb1 */    "gy-----",
  ];
  const weekdayLabels = ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"];

  const heatColors = {
    g: "var(--sp-grad-money)",
    y: "var(--sp-grad-warn)",
    r: "var(--sp-grad-pain)",
    "-": "rgba(255,255,255,.04)",
  };
  /* Цвет ring'а для выделенной ячейки — берём по статусу клетки,
     чтобы кольцо тонально совпадало с её градиентом. */
  const ringByStatus = {
    g: "rgba(46,219,159,.6)",
    y: "rgba(255,212,121,.7)",
    r: "rgba(255,180,168,.7)",
    "-": "rgba(255,255,255,.4)",
  };

  /* Заголовок для тултипа — формулируем поведение, цвет и подпись
     согласовываем с семантикой клетки. */
  const tipCopy = (cell) => {
    if (!cell) return null;
    const map = {
      g: { label: "Встал сразу", tone: "var(--sp-money-300)" },
      y: { label: `${cell.snoozes ?? "1–2"} откладывани${(cell.snoozes ?? 2) === 1 ? "е" : "я"}`, tone: "var(--sp-warn-300)" },
      r: { label: `${cell.snoozes ?? "3+"} откладываний`, tone: "var(--sp-pain-300)" },
      "-": { label: "Не было будильника", tone: "var(--sp-fg-3)" },
    };
    return map[cell.status] || map["-"];
  };
  const tip = tipCopy(tappedCell);

  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>

      {/* Page header — без back button, тот же паттерн что у Будильники /
          Кошелёк. Большой h1, разделитель снизу. */}
      <div style={{
        padding: "16px 16px 16px",
        background: "var(--sp-bg-0)",
        borderBottom: "1px solid var(--sp-white-06)",
        flexShrink: 0, position: "relative", zIndex: 2,
      }}>
        <div style={{ font: "var(--sp-t-h1)", color: "var(--sp-fg-1)", letterSpacing: "-.02em" }}>Статистика</div>
      </div>

      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "16px 16px 20px", display: "flex", flexDirection: "column", gap: 12 }}>
          {/* HERO — Серия. Главный мотивационный элемент. */}
          <SPCard padding="24px 20px" radius={24}>
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

            {/* Heat-map: календарь текущего месяца (январь 2026, 5 недель).
                7 cols × 5 rows. Дни Пн—Вс в шапке. Без левой колонки дат
                и без легенды — компактнее. Клетки используют сигнатурные
                градиенты (money / warn / pain).
                Если задан tappedCell — соответствующая клетка получает ring
                и над ней показывается тултип. */}
            <div style={{
              marginTop: 20,
              display: "grid",
              gridTemplateColumns: "repeat(7, 1fr)",
              gap: 4,
              position: "relative",
            }}>
              {/* Header row — weekday labels */}
              {weekdayLabels.map((w, i) => (
                <div key={`h-${i}`} style={{
                  font: "600 10px/12px var(--sp-font-body)",
                  color: "var(--sp-fg-3)",
                  textAlign: "center",
                  letterSpacing: ".04em",
                  textTransform: "uppercase",
                  paddingBottom: 4,
                }}>{w}</div>
              ))}

              {/* 5 weeks × 7 day cells. Tooltip — child of the selected cell
                  itself (cell имеет position:relative), чтобы CSS Grid не
                  резервировал для тултипа дополнительный slot и не сдвигал
                  соседние клетки. */}
              {heatmapRows.flatMap((row, ri) => row.split("").map((c, ci) => {
                const isSel = tappedCell && tappedCell.row === ri && tappedCell.col === ci;
                return (
                  <div key={`c-${ri}-${ci}`} style={{
                    aspectRatio: "1/1",
                    borderRadius: 5,
                    background: heatColors[c] || heatColors["-"],
                    boxShadow: isSel ? `0 0 0 2px var(--sp-bg-1), 0 0 0 4px ${ringByStatus[c] || ringByStatus["-"]}` : "none",
                    position: "relative",
                    zIndex: isSel ? 3 : 1,
                  }}>
                    {isSel && tip && (
                      <div style={{
                        position: "absolute",
                        left: "50%",
                        top: "calc(100% + 10px)",
                        transform: "translateX(-50%)",
                        minWidth: 180,
                        padding: "10px 14px",
                        borderRadius: 12,
                        background: "var(--sp-bg-3)",
                        border: "1px solid var(--sp-white-08)",
                        boxShadow: "0 12px 32px rgba(0,0,0,.5)",
                        whiteSpace: "nowrap",
                        pointerEvents: "none",
                      }} aria-hidden>
                        {/* Arrow ↑ pointing to the cell */}
                        <div style={{
                          position: "absolute",
                          left: "50%",
                          top: -6,
                          transform: "translateX(-50%) rotate(45deg)",
                          width: 12, height: 12,
                          background: "var(--sp-bg-3)",
                          borderTop: "1px solid var(--sp-white-08)",
                          borderLeft: "1px solid var(--sp-white-08)",
                        }} aria-hidden/>
                        <div style={{
                          font: "700 14px/18px var(--sp-font-body)",
                          color: "var(--sp-fg-1)",
                          letterSpacing: "-.01em",
                        }}>{tappedCell.date}</div>
                        <div style={{
                          marginTop: 4,
                          display: "flex", alignItems: "center", gap: 6,
                        }}>
                          <span style={{
                            width: 8, height: 8, borderRadius: 2,
                            background: heatColors[tappedCell.status],
                          }} aria-hidden/>
                          <span style={{
                            font: "600 12px/16px var(--sp-font-body)",
                            color: tip.tone,
                          }}>{tip.label}</span>
                          {tappedCell.spent ? (
                            <span style={{
                              font: "500 12px/16px var(--sp-font-body)",
                              color: "var(--sp-fg-3)",
                              marginLeft: 2,
                            }}>· −{fmtRub(tappedCell.spent)}</span>
                          ) : null}
                        </div>
                      </div>
                    )}
                  </div>
                );
              }))}
            </div>
          </SPCard>

          {/* По дням недели — bar chart с подсветкой худшего дня. */}
          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>По дням недели</div>
            <div style={{ marginTop: 8, display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12 }}>
              <div>
                <div style={{ font: "var(--sp-t-h3)", color: "#FFF", letterSpacing: "-.01em" }}>
                  Чаще всего&nbsp;— <span style={{ color: "var(--sp-pain-300)" }}>{worstDayFull}</span>
                </div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>
                  За последние 4 недели
                </div>
              </div>
            </div>

            <div style={{ marginTop: 18, display: "flex", gap: 8, alignItems: "flex-end", height: 132 }}>
              {byWeekday.map((d, i) => {
                const isWorst = i === worstIdx;
                const isZero = d.n === 0;
                const h = isZero ? 4 : Math.max(8, (d.n / wdMax) * 100);
                return (
                  <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6, height: "100%" }}>
                    <div style={{
                      font: "700 12px/14px var(--sp-font-body)",
                      color: isWorst ? "var(--sp-pain-300)" : isZero ? "var(--sp-fg-4)" : "var(--sp-fg-2)",
                      fontVariantNumeric: "tabular-nums",
                    }}>{d.n}</div>
                    <div style={{ flex: 1, width: "100%", display: "flex", alignItems: "flex-end" }}>
                      <div style={{
                        width: "100%",
                        height: `${h}%`,
                        borderRadius: 6,
                        background: isZero
                          ? "transparent"
                          : isWorst ? "var(--sp-grad-pain)" : "var(--sp-white-12)",
                        border: isZero ? "1.5px dashed var(--sp-white-12)" : "none",
                        boxShadow: isWorst ? "0 4px 14px rgba(244,82,63,.30)" : "none",
                      }}/>
                    </div>
                    <div className="sp-meta" style={{
                      color: isWorst ? "var(--sp-fg-1)" : "var(--sp-fg-3)",
                      fontSize: 11,
                      fontWeight: isWorst ? 700 : 500,
                    }}>{d.l}</div>
                  </div>
                );
              })}
            </div>
          </SPCard>

          {/* Динамика по неделям — тренд лучше/хуже */}
          <SPCard padding={20} radius={20}>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Динамика откладываний</div>

            <div style={{ marginTop: 8, display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12 }}>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <span style={{ font: "var(--sp-t-h3)", color: "#FFF", letterSpacing: "-.01em" }}>{trendHeadline}</span>
                  {!trendSame && (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={trendColor} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                      {trendBetter
                        ? <><path d="M7 7l10 10"/><path d="M17 9v8h-8"/></>
                        : <><path d="M7 17L17 7"/><path d="M9 7h8v8"/></>}
                    </svg>
                  )}
                </div>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>
                  {diff === 0
                    ? "Столько же, сколько на прошлой неделе"
                    : `${diff > 0 ? "+" : ""}${diff} к прошлой неделе`}
                </div>
              </div>
              <div style={{ textAlign: "right" }}>
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>Эта неделя</div>
                <div style={{
                  font: "var(--sp-t-money-md)",
                  color: trendColor,
                  fontVariantNumeric: "tabular-nums",
                }}>{thisWk}</div>
              </div>
            </div>

            <div style={{ marginTop: 18, display: "flex", gap: 6, alignItems: "flex-end", height: 100 }}>
              {weeks.map((w, i) => {
                const h = Math.max(6, (w.n / wMax) * 100);
                return (
                  <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 6, height: "100%" }}>
                    <div style={{ flex: 1, width: "100%", display: "flex", alignItems: "flex-end" }}>
                      <div style={{
                        width: "100%",
                        height: `${h}%`,
                        borderRadius: 4,
                        background: w.current
                          ? (trendBetter ? "var(--sp-grad-money)" : trendSame ? "var(--sp-white-24)" : "var(--sp-grad-pain)")
                          : "var(--sp-white-12)",
                      }}/>
                    </div>
                  </div>
                );
              })}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
              <span className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>8 недель назад</span>
              <span className="sp-meta" style={{ color: "var(--sp-fg-1)", fontWeight: 600 }}>эта неделя</span>
            </div>
          </SPCard>
        </div>
      </div>

      {/* Bottom tab bar — Stats — основной таб. */}
      <SPTabBar active="stats" />
    </div>
  );
}

/* 28. SETTINGS */
function SettingsV2() {
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--sp-bg-0)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
      <SPStatusBar time="9:42" tone="light"/>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Настройки</div>
          <div style={{ width: 36 }}/>
        </div>

        <div style={{ padding: "20px 16px 0", flex: 1, overflowY: "auto", display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Section: финансы */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Финансы</div>
            <SPCard padding="4px 20px" radius={16}>
              <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-warn-400)"}}/>} title="Цена откладывания по умолчанию" trailing={<><span style={{font:"var(--sp-t-money-md)", color: "var(--sp-warn-400)"}}>{fmtRub(50)}</span><IconChevR size={16}/></>}/>
              <SPRow divider={false} leading={<IconClock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Длительность откладывания" trailing={<><span className="sp-meta">9 мин</span><IconChevR size={16}/></>}/>
            </SPCard>
          </div>

          {/* Section: уведомления и звук */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Звук и уведомления</div>
            <SPCard padding="4px 20px" radius={16}>
              <SPRow leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Громкость" trailing={<><span className="sp-meta">80%</span><IconChevR size={16}/></>}/>
              <SPRow leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Critical Alerts" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow divider={false} leading={<IconClock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Вибрация" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            </SPCard>
          </div>

          {/* Section: правила */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Правила</div>
            <SPCard padding="4px 20px" radius={16}>
              <SPRow leading={<IconFlame size={20} style={{color:"var(--sp-pain-400)"}}/>} title="Прогрессивная цена" subtitle="50 → 100 → 200 → 400" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-money-400)"}}/>} title="Бонус за серию" subtitle="+10% к балансу за 7 дней" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
              <SPRow divider={false} leading={<IconLock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Защита от скуки" subtitle="Не давать выключить во время звонка" trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
            </SPCard>
          </div>

          {/* Section: пригласить друга — отдельный блок с двумя действиями.
              Свой код — копируется. Поле «Код друга» — ввод чужого кода прямо здесь,
              чтобы не идти на отдельный экран. Дублирует функционал экрана «Пригласить». */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Пригласить друга</div>
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

          {/* Section: остальное */}
          <div>
            <div className="sp-caps" style={{ color: "var(--sp-fg-3)", padding: "0 8px 8px" }}>Прочее</div>
            <SPCard padding="4px 20px" radius={16}>
              <SPRow leading={<IconBell size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Поддержка"/>
              <SPRow leading={<IconLock size={20} style={{color:"var(--sp-fg-3)"}}/>} title="Конфиденциальность"/>
              <SPRow divider={false} title={<span style={{color:"var(--sp-pain-400)"}}>Выйти из аккаунта</span>}/>
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
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "16px 16px 0", display: "flex", justifyContent: "space-between", alignItems: "center", height: 44 }}>
          <button style={{ width: 36, height: 36, borderRadius: 18, border: 0, background: "var(--sp-white-06)", color: "var(--sp-fg-1)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <IconBack size={18}/>
          </button>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Пригласить</div>
          <div style={{ width: 36 }}/>
        </div>

        {/* Hero */}
        <div style={{ padding: "16px 16px 0" }}>
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
        <div style={{ padding: "20px 16px 0" }}>
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
        <div style={{ padding: "20px 16px 0" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 8 }}>Код друга</div>
          <SPCard padding="12px 16px" radius={16}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <input
                value={friendCode}
                onChange={(e)=>setFriendCode(e.target.value.toUpperCase())}
                placeholder="Например, WAKEUP-7K2"
                style={{
                  flex: 1, border: 0, outline: "none", background: "transparent",
                  color: "#FFF", caretColor: "var(--sp-money-400)",
                  font: "16px/22px var(--sp-font-mono)", letterSpacing: ".1em",
                  padding: "8px 8px",
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
        <div style={{ padding: "20px 16px 0", flex: 1, overflowY: "auto" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginBottom: 10 }}>Друзья</div>
          <SPCard padding="4px 20px" radius={16}>
            <SPRow leading={
              <div style={{ width: 36, height: 36, borderRadius: 18, background: "var(--sp-grad-money)",
                display: "flex", alignItems: "center", justifyContent: "center", font: "var(--sp-t-h4)", color: "var(--sp-fg-on-money)" }}>М</div>
            } title="Маша К." subtitle="Продержалась 7 дней"
              trailing={<span style={{font:"var(--sp-t-money-md)", color:"var(--sp-money-400)"}}>+{fmtRub(200)}</span>}/>
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

        <div style={{ padding: "16px 16px 32px", display: "flex", flexDirection: "column", gap: 8 }}>
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
      <div style={{ paddingTop: 54, padding: "54px 16px 32px", height: "100%", display: "flex", flexDirection: "column" }}>
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
            За эту неделю списано <span style={{ color: "var(--sp-pain-400)", fontFamily: "var(--sp-font-mono)" }}>−{fmtRub(750)}</span>.
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
                <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>Сегодня поздно лёг — встаём в 08:00</div>
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
