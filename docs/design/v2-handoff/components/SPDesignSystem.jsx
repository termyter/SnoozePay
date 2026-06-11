// SnoozePay Design System — компоненты страницы

const { useState: dsS } = React;

/* ============================================================
   Layout primitives
   ============================================================ */
function DSPage({ children }) {
  return (
    <div style={{ minHeight: "100vh", background: "var(--sp-bg-0)", color: "var(--sp-fg-1)" }}>
      {children}
    </div>
  );
}

function DSHero() {
  return (
    <div style={{ position: "relative", padding: "120px 80px 80px", overflow: "hidden",
      borderBottom: "1px solid var(--sp-white-08)" }}>
      <div style={{ position: "absolute", right: -100, top: -100, width: 600, height: 600, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(46,219,159,.12) 0%, transparent 60%)", filter: "blur(40px)" }}/>
      <div style={{ position: "absolute", left: -200, bottom: -200, width: 600, height: 600, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(255,184,77,.10) 0%, transparent 60%)", filter: "blur(40px)" }}/>

      <div style={{ position: "relative", maxWidth: 1200, margin: "0 auto" }}>
        <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>SnoozePay · Design System v1.0</div>
        <h1 style={{ font: "800 88px/92px var(--sp-font-display)", letterSpacing: "-.03em", color: "#FFF",
          margin: "16px 0 0", maxWidth: 900 }}>
          Будильник, где<br/>
          откладывание<br/>
          <span style={{ background: "var(--sp-grad-money)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>стоит денег</span>.
        </h1>
        <p style={{ font: "var(--sp-t-body-lg)", color: "var(--sp-fg-2)", maxWidth: 640, marginTop: 24 }}>
          Дизайн-система SnoozePay. Денежная метафорика, монотипные суммы, тёплый Dawn-язык.
          Адаптировано из Protrainer DS под платёжно-будильничную задачу.
        </p>

        {/* быстрые метрики */}
        <div style={{ display: "flex", gap: 48, marginTop: 56, flexWrap: "wrap" }}>
          {[
            { l: "Цветовых токенов", v: "60+" },
            { l: "Шрифтовых ролей", v: "16" },
            { l: "Компонентов", v: "13" },
            { l: "Иконок", v: "20" },
          ].map(s => (
            <div key={s.l}>
              <div style={{ font: "var(--sp-t-money-lg)", color: "#FFF", fontVariantNumeric: "tabular-nums" }}>{s.v}</div>
              <div className="sp-caps" style={{ color: "var(--sp-fg-3)", marginTop: 4 }}>{s.l}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function DSSection({ id, eyebrow, title, subtitle, children }) {
  return (
    <section id={id} style={{ padding: "96px 80px", borderBottom: "1px solid var(--sp-white-06)",
      maxWidth: 1360, margin: "0 auto" }}>
      <div style={{ marginBottom: 48 }}>
        <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>{eyebrow}</div>
        <h2 style={{ font: "var(--sp-t-h1)", color: "#FFF", letterSpacing: "-.02em", margin: "12px 0 0",
          fontSize: 48, lineHeight: "56px" }}>{title}</h2>
        {subtitle && <p style={{ font: "var(--sp-t-body-lg)", color: "var(--sp-fg-2)", maxWidth: 720, marginTop: 12 }}>{subtitle}</p>}
      </div>
      {children}
    </section>
  );
}

/* ============================================================
   PRINCIPLES
   ============================================================ */
function DSPrinciples() {
  const principles = [
    { n: "01", t: "Деньги — главный визуальный ритм", d: "Любая сумма пишется монотипным шрифтом, выровнена по разрядам, с tabular-nums. Зелёное — заработано, янтарное — обычная цена откладывания, красное — прогрессивный штраф." },
    { n: "02", t: "Сценарий важнее эстетики", d: "Утро в 07:00, глаза не открываются. Кнопки в firing-экране должны попадаться большим пальцем без прицеливания. Минимум 56px, максимум 2 действия в фокусе." },
    { n: "03", t: "Тёплый рассвет вместо холодного хайтека", d: "Dawn-палитра (тёмно-янтарный → красный) — фирменная атмосфера. Никаких голубых будильников. Свет «дышит» — лёгкое 8-секундное альфа-движение." },
    { n: "04", t: "Прозрачность боли", d: "Никаких скрытых списаний. Всегда показано: цена следующего откладывания, остаток баланса, сколько списано за сегодня. Цена — обязательно ДО действия, не после." },
    { n: "05", t: "Прогрессив — про дисциплину, не про наказание", d: "Цена ×2 каждое откладывание — это не штраф, это эскалация ставок самим пользователем. Тон: нейтральный, прямой, без морализаторства." },
  ];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(380px, 1fr))", gap: 1,
      background: "var(--sp-white-08)", border: "1px solid var(--sp-white-08)", borderRadius: 24, overflow: "hidden" }}>
      {principles.map(p => (
        <div key={p.n} style={{ background: "var(--sp-bg-1)", padding: 32 }}>
          <div style={{ font: "var(--sp-t-money-md)", color: "var(--sp-fg-3)", fontVariantNumeric: "tabular-nums" }}>{p.n}</div>
          <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "12px 0 8px", letterSpacing: "-.01em" }}>{p.t}</h3>
          <p style={{ font: "var(--sp-t-body)", color: "var(--sp-fg-2)", margin: 0 }}>{p.d}</p>
        </div>
      ))}
    </div>
  );
}

/* ============================================================
   COLORS
   ============================================================ */
function ColorSwatch({ name, value, fg = "#FFF", note }) {
  return (
    <div style={{ borderRadius: 16, overflow: "hidden", border: "1px solid var(--sp-white-08)" }}>
      <div style={{ background: value, height: 96, display: "flex", alignItems: "flex-end", padding: 14 }}>
        <div style={{ font: "var(--sp-t-meta)", color: fg, fontFamily: "var(--sp-font-mono)" }}>{value}</div>
      </div>
      <div style={{ padding: 14, background: "var(--sp-bg-1)" }}>
        <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF" }}>{name}</div>
        {note && <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>{note}</div>}
      </div>
    </div>
  );
}

function ColorRamp({ title, subtitle, colors }) {
  return (
    <div style={{ marginBottom: 56 }}>
      <div style={{ marginBottom: 20 }}>
        <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: 0 }}>{title}</h3>
        <p className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 4, maxWidth: 640 }}>{subtitle}</p>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 16 }}>
        {colors.map(c => <ColorSwatch key={c.name} {...c}/>)}
      </div>
    </div>
  );
}

function DSColors() {
  return (
    <>
      <ColorRamp
        title="Money — основная палитра"
        subtitle="Зелёный = ваши деньги. Используется для CTA, успешных операций, баланса, заработанного. Никогда — для деструктивных действий."
        colors={[
          { name: "money-300", value: "#5EEAB8", fg: "#052016", note: "Бэкграунды, акценты на тёмном" },
          { name: "money-400", value: "#2EDB9F", fg: "#052016", note: "Иконки, лёгкие фоны" },
          { name: "money-500", value: "#10B981", fg: "#FFF", note: "Primary CTA, основной зелёный" },
          { name: "money-600", value: "#0E9D6E", fg: "#FFF", note: "Hover state" },
          { name: "money-700", value: "#0B7A56", fg: "#FFF", note: "Pressed, нижний край градиента" },
        ]}
      />
      <ColorRamp
        title="Warn — обычное откладывание"
        subtitle="Цена обычного откладывания, баланс ниже комфортного, мягкие предупреждения. Тёплый янтарь, не алярмист."
        colors={[
          { name: "warn-300", value: "#FFD479", fg: "#1A0F00" },
          { name: "warn-400", value: "#FFB84D", fg: "#1A0F00", note: "Иконка цены откладывания" },
          { name: "warn-500", value: "#F59E0B", fg: "#1A0F00", note: "Default snooze price" },
          { name: "warn-600", value: "#C97A06", fg: "#FFF" },
        ]}
      />
      <ColorRamp
        title="Pain — прогрессив, потери"
        subtitle="Прогрессивное откладывание (×2/×4/×8), просроченные платежи, тяжёлые предупреждения. Используется СДЕРЖАННО — каждое появление должно быть мотивированным."
        colors={[
          { name: "pain-300", value: "#FFB4A8", fg: "#3A0E08" },
          { name: "pain-400", value: "#FF7A6B", fg: "#FFF" },
          { name: "pain-500", value: "#F4523F", fg: "#FFF", note: "Прогрессив, дорогой штраф" },
          { name: "pain-600", value: "#D43A28", fg: "#FFF" },
        ]}
      />
      <ColorRamp
        title="Surfaces — фоны"
        subtitle="Тёмная тема — основная. Light используется только для печати/документации. Firing-экран ВСЕГДА тёмный, даже в light-режиме."
        colors={[
          { name: "bg-0", value: "#060912", note: "App bg deepest" },
          { name: "bg-1", value: "#0E1320", note: "Card" },
          { name: "bg-2", value: "#161C2E", note: "Raised card" },
          { name: "bg-3", value: "#1F2740", note: "Active chip / sheet" },
          { name: "bg-4", value: "#2A3354", note: "Hover/focus" },
        ]}
      />
      {/* Градиенты */}
      <div style={{ marginTop: 16 }}>
        <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 20px" }}>Сигнатурные градиенты</h3>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 16 }}>
          {[
            { name: "grad-money", value: "linear-gradient(135deg, #2EDB9F 0%, #10B981 60%, #0B7A56 100%)" },
            { name: "grad-warn",  value: "linear-gradient(135deg, #FFD479 0%, #F59E0B 60%, #C97A06 100%)" },
            { name: "grad-pain",  value: "linear-gradient(135deg, #FFB4A8 0%, #F4523F 55%, #D43A28 100%)" },
            { name: "grad-dawn",  value: "linear-gradient(180deg, #14122A 0%, #2B1A0E 50%, #4A2410 100%)" },
            { name: "grad-night", value: "radial-gradient(120% 80% at 50% 0%, #1B2030 0%, #0E1320 55%, #060912 100%)" },
          ].map(g => (
            <div key={g.name} style={{ borderRadius: 16, overflow: "hidden", border: "1px solid var(--sp-white-08)" }}>
              <div style={{ height: 120, background: g.value }}/>
              <div style={{ padding: 14, background: "var(--sp-bg-1)" }}>
                <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF" }}>{g.name}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

/* ============================================================
   TYPOGRAPHY
   ============================================================ */
function TypeRow({ name, font, sample, note }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "240px 1fr 280px", gap: 32, alignItems: "baseline",
      padding: "24px 0", borderBottom: "1px solid var(--sp-white-06)" }}>
      <div>
        <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF" }}>{name}</div>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2, fontFamily: "var(--sp-font-mono)" }}>{font}</div>
      </div>
      <div style={{ font, color: "#FFF", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" }}>{sample}</div>
      <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>{note}</div>
    </div>
  );
}

function DSType() {
  return (
    <>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 32, marginBottom: 56 }}>
        <div style={{ background: "var(--sp-bg-1)", borderRadius: 24, padding: 32, border: "1px solid var(--sp-white-06)" }}>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>Display & Body</div>
          <div style={{ font: "800 80px/80px var(--sp-font-display)", color: "#FFF", marginTop: 8,
            letterSpacing: "-.03em" }}>Manrope</div>
          <p style={{ font: "var(--sp-t-body-lg)", color: "var(--sp-fg-2)", marginTop: 12 }}>
            Геометрический грот с гуманистическим характером. Хорошо читается на маленьких экранах,
            держит вес от 400 до 800.
          </p>
        </div>
        <div style={{ background: "var(--sp-bg-1)", borderRadius: 24, padding: 32, border: "1px solid var(--sp-white-06)" }}>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>Money & Time</div>
          <div style={{ font: "700 64px/72px var(--sp-font-mono)", color: "#FFF", marginTop: 8,
            letterSpacing: "-.02em" }}>{fmtRub(1250)}</div>
          <p style={{ font: "var(--sp-t-body-lg)", color: "var(--sp-fg-2)", marginTop: 12 }}>
            <span style={{ fontFamily: "var(--sp-font-mono)" }}>JetBrains&nbsp;Mono</span>.
            Все суммы и таймеры — моноширинные. Цифры выровнены по разрядам (tabular-nums),
            ноль с косой чертой не используется.
          </p>
        </div>
      </div>

      <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 8px" }}>Шкала ролей</h3>
      <p className="sp-meta" style={{ color: "var(--sp-fg-3)", marginBottom: 16 }}>16 ролей: 6 для текста, 4 для денег, 2 для часов, 4 служебных.</p>

      <div>
        <TypeRow name="display"   font="800 88px/92px Manrope"          sample="−400 ₽ за лень" note="Streak modal hero, big-moment overlays" />
        <TypeRow name="h1"        font="800 32px/40px Manrope"          sample="Баланс — это рычаг" note="Onboarding, экран-герой, top-of-screen titles" />
        <TypeRow name="h2"        font="700 24px/32px Manrope"          sample="Создать будильник" note="Sheet titles, секции внутри экрана" />
        <TypeRow name="h3"        font="700 20px/28px Manrope"          sample="Понедельник, 07:00" note="Subsection, cards" />
        <TypeRow name="h4"        font="700 17px/24px Manrope"          sample="Способы оплаты" note="Listrows, dense titles" />
        <TypeRow name="body-lg"   font="500 17px/26px Manrope"          sample="Чтобы будильник работал, пополните баланс."  note="Onboarding paragraphs, важные пояснения" />
        <TypeRow name="body"      font="500 15px/22px Manrope"          sample="Будни · Понедельник · обычный режим" note="Default text, supporting copy" />
        <TypeRow name="meta"      font="500 13px/18px Manrope"          sample="Apple Pay · 3D Secure" note="Captions, meta-info, timestamps" />
        <TypeRow name="caps"      font="700 12px/16px Manrope (track .12em)" sample="ВАЛЮТА · СЛЕДУЮЩЕЕ ОТКЛАДЫВАНИЕ" note="Eyebrow labels, секционные заголовки" />
        <TypeRow name="money-xl"  font="700 56px/60px JetBrains Mono"   sample="200 ₽" note="Hero сумма (firing screen, deposit)" />
        <TypeRow name="money-lg"  font="700 32px/36px JetBrains Mono"   sample="1 250 ₽" note="Balance card" />
        <TypeRow name="money-md"  font="700 20px/26px JetBrains Mono"   sample="50 ₽" note="Row sums, цена откладывания в карточке" />
        <TypeRow name="money-sm"  font="600 14px/20px JetBrains Mono"   sample="−50.00" note="Meta цены, мелкие числа" />
        <TypeRow name="clock-xl"  font="200 96px/96px JetBrains Mono"   sample="7:14" note="Firing screen — большое время" />
        <TypeRow name="clock-lg"  font="300 64px/64px JetBrains Mono"   sample="7:00" note="Alarm card time" />
      </div>
    </>
  );
}

/* ============================================================
   SPACING / RADII / SHADOWS
   ============================================================ */
function DSSpacing() {
  const spaces = [
    { n: "1", v: 4 }, { n: "2", v: 8 }, { n: "3", v: 12 }, { n: "4", v: 16 },
    { n: "5", v: 20 }, { n: "6", v: 24 }, { n: "7", v: 32 }, { n: "8", v: 40 },
    { n: "9", v: 56 }, { n: "10", v: 72 },
  ];
  const radii = [
    { n: "xs", v: 8 }, { n: "sm", v: 12 }, { n: "md", v: 16 }, { n: "lg", v: 20 },
    { n: "xl", v: 28 }, { n: "2xl", v: 36 }, { n: "pill", v: 999 },
  ];
  return (
    <>
      {/* Spacing scale */}
      <div style={{ marginBottom: 48 }}>
        <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 8px" }}>Spacing — 4px base</h3>
        <p className="sp-meta" style={{ color: "var(--sp-fg-3)", marginBottom: 24 }}>Всё кратно 4. Используется через CSS-переменные `--sp-1`…`--sp-10`.</p>
        <div style={{ background: "var(--sp-bg-1)", borderRadius: 20, padding: 24, border: "1px solid var(--sp-white-06)" }}>
          {spaces.map(s => (
            <div key={s.n} style={{ display: "grid", gridTemplateColumns: "80px 80px 1fr", gap: 16,
              alignItems: "center", padding: "10px 0" }}>
              <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF" }}>--sp-{s.n}</div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)" }}>{s.v}px</div>
              <div style={{ height: 14, width: s.v, background: "var(--sp-grad-money)", borderRadius: 4 }}/>
            </div>
          ))}
        </div>
      </div>

      {/* Radii */}
      <div style={{ marginBottom: 48 }}>
        <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 24px" }}>Радиусы</h3>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(160px, 1fr))", gap: 16 }}>
          {radii.map(r => (
            <div key={r.n} style={{ borderRadius: 16, overflow: "hidden", background: "var(--sp-bg-1)",
              border: "1px solid var(--sp-white-06)", padding: 24, textAlign: "center" }}>
              <div style={{ width: 80, height: 80, margin: "0 auto",
                background: "var(--sp-grad-money)",
                borderRadius: r.v === 999 ? "50%" : r.v }}/>
              <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF", marginTop: 16 }}>--sp-r-{r.n}</div>
              <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)" }}>
                {r.v === 999 ? "999px" : `${r.v}px`}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Shadows */}
      <div>
        <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 24px" }}>Тени · цветные elevations</h3>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 24,
          padding: 32, background: "var(--sp-bg-1)", borderRadius: 20, border: "1px solid var(--sp-white-06)" }}>
          {[
            { n: "shadow-1", v: "0 2px 8px rgba(0,0,0,.35)", bg: "var(--sp-bg-2)" },
            { n: "shadow-2", v: "0 8px 24px rgba(0,0,0,.45)", bg: "var(--sp-bg-2)" },
            { n: "shadow-money", v: "0 8px 22px -6px rgba(16,185,129,.40)", bg: "var(--sp-grad-money)" },
            { n: "shadow-warn",  v: "0 8px 22px -6px rgba(245,158,11,.40)", bg: "var(--sp-grad-warn)" },
            { n: "shadow-pain",  v: "0 8px 22px -6px rgba(244,82,63,.45)", bg: "var(--sp-grad-pain)" },
          ].map(s => (
            <div key={s.n} style={{ textAlign: "center" }}>
              <div style={{ width: "100%", height: 80, borderRadius: 16, background: s.bg, boxShadow: s.v }}/>
              <div style={{ font: "var(--sp-t-money-sm)", color: "#FFF", marginTop: 16 }}>--sp-{s.n}</div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

/* ============================================================
   COMPONENTS
   ============================================================ */
function DSComponentBlock({ title, code, children }) {
  return (
    <div style={{ background: "var(--sp-bg-1)", borderRadius: 24, border: "1px solid var(--sp-white-06)",
      overflow: "hidden", marginBottom: 24 }}>
      <div style={{ padding: "16px 24px", borderBottom: "1px solid var(--sp-white-06)",
        display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>{title}</div>
        {code && <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)" }}>{code}</div>}
      </div>
      <div style={{ padding: 32, background:
        "repeating-linear-gradient(45deg, var(--sp-white-04) 0 1px, transparent 1px 12px), var(--sp-bg-1)",
        display: "flex", flexWrap: "wrap", gap: 16, alignItems: "center", justifyContent: "center" }}>
        {children}
      </div>
    </div>
  );
}

function DSComponents() {
  return (
    <>
      <DSComponentBlock title="Buttons" code="<SPButton variant size>">
        <SPButton variant="money" size="lg">Оплатить · 200 ₽</SPButton>
        <SPButton variant="pain" size="lg">Удалить</SPButton>
        <SPButton variant="quiet" size="lg">Отмена</SPButton>
        <SPButton variant="ghost" size="md">Позже</SPButton>
        <SPButton variant="money" size="sm">Малый</SPButton>
      </DSComponentBlock>

      <DSComponentBlock title="Snooze price" code="<SPSnoozePrice tone>">
        <SPSnoozePrice price={50}  minutes={9} tone="warn" hint="обычная цена"/>
        <SPSnoozePrice price={200} minutes={9} tone="warn" hint="следующее откладывание"/>
        <SPSnoozePrice price={800} minutes={9} tone="pain" hint="прогрессив × 16"/>
      </DSComponentBlock>

      <DSComponentBlock title="Pills · бейджи" code="<SPPill tone>">
        <SPPill>Будни</SPPill>
        <SPPill tone="money">+50 ₽</SPPill>
        <SPPill tone="warn">×2</SPPill>
        <SPPill tone="pain">−400 ₽</SPPill>
      </DSComponentBlock>

      <DSComponentBlock title="Switch & Segmented" code="<SPSwitch>, <SPSegmented>">
        <SPSwitch checked={true} onChange={()=>{}}/>
        <SPSwitch checked={false} onChange={()=>{}}/>
        <div style={{ width: 280 }}>
          <SPSegmented options={[{value:"a",label:"Будни"},{value:"b",label:"Выходные"},{value:"c",label:"Спорт"}]} value="a" onChange={()=>{}}/>
        </div>
      </DSComponentBlock>

      <DSComponentBlock title="Balance card" code="<SPBalanceCard>">
        <div style={{ width: 360 }}>
          <SPBalanceCard balance="1 250 ₽" delta="+200 ₽ за неделю" hint="Баланс · хватит на 25 откладываний"/>
        </div>
      </DSComponentBlock>

      <DSComponentBlock title="Amount preset · выбор баланса" code="<SPAmountPreset>">
        <SPAmountPreset value="200 ₽"  label="Попробовать"/>
        <SPAmountPreset value="500 ₽"  label="Серьёзно" selected popular/>
        <SPAmountPreset value="1000 ₽" label="Решительно"/>
      </DSComponentBlock>

      <DSComponentBlock title="Row · строка списка" code="<SPRow>">
        <div style={{ width: 360, background: "var(--sp-bg-2)", borderRadius: 16, padding: 4 }}>
          <SPRow leading={<IconCoin size={20} style={{color:"var(--sp-warn-400)"}}/>}
                 title="Цена откладывания" trailing={<><span style={{font:"var(--sp-t-money-md)", color:"var(--sp-warn-400)"}}>50 ₽</span><IconChevR size={16}/></>}/>
          <SPRow leading={<IconFlame size={20} style={{color:"var(--sp-pain-400)"}}/>}
                 title="Прогрессив" subtitle="50 → 100 → 200 → 400"
                 trailing={<SPSwitch checked={true} onChange={()=>{}}/>}/>
          <SPRow divider={false}
                 leading={<IconSound size={20} style={{color:"var(--sp-fg-3)"}}/>}
                 title="Звук" trailing={<><span className="sp-meta">Soft Dawn</span><IconChevR size={16}/></>}/>
        </div>
      </DSComponentBlock>
    </>
  );
}

/* ============================================================
   ICONS
   ============================================================ */
function DSIcons() {
  const icons = [
    { n: "alarm", c: <IconAlarm/> }, { n: "wallet", c: <IconWallet/> },
    { n: "stats", c: <IconStats/> }, { n: "chart", c: <IconChart/> },
    { n: "plus", c: <IconPlus/> }, { n: "back", c: <IconBack/> },
    { n: "close", c: <IconClose/> }, { n: "check", c: <IconCheck/> },
    { n: "chev-r", c: <IconChevR/> }, { n: "bell", c: <IconBell/> },
    { n: "flame", c: <IconFlame/> }, { n: "coin", c: <IconCoin/> },
    { n: "shield", c: <IconShield/> }, { n: "sound", c: <IconSound/> },
    { n: "clock", c: <IconClock/> }, { n: "trash", c: <IconTrash/> },
    { n: "arrow-up", c: <IconArrowUp/> }, { n: "arrow-dn", c: <IconArrowDn/> },
    { n: "user", c: <IconUser/> }, { n: "lock", c: <IconLock/> },
  ];
  return (
    <>
      <p className="sp-meta" style={{ color: "var(--sp-fg-3)", marginBottom: 24 }}>
        24×24, обводка 1.75, lucide-style. На бэкграунде: <code style={{ fontFamily: "var(--sp-font-mono)" }}>currentColor</code>,
        стили задаются через color родителя. Для мелких контекстов поддерживается size=20, 18, 16.
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))", gap: 1,
        background: "var(--sp-white-06)", border: "1px solid var(--sp-white-06)", borderRadius: 16, overflow: "hidden" }}>
        {icons.map(i => (
          <div key={i.n} style={{ background: "var(--sp-bg-1)", padding: 20, textAlign: "center",
            display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
            <div style={{ color: "#FFF" }}>{React.cloneElement(i.c, { size: 32 })}</div>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)", fontFamily: "var(--sp-font-mono)" }}>{i.n}</div>
          </div>
        ))}
      </div>
    </>
  );
}

/* ============================================================
   MOTION
   ============================================================ */
function MotionDemo({ duration, ease, label, sub }) {
  const [on, setOn] = dsS(false);
  return (
    <div style={{ background: "var(--sp-bg-1)", borderRadius: 16, border: "1px solid var(--sp-white-06)",
      padding: 20 }}>
      <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>{label}</div>
      <div style={{ font: "var(--sp-t-money-sm)", color: "var(--sp-fg-3)", margin: "8px 0 16px",
        fontFamily: "var(--sp-font-mono)" }}>{sub}</div>
      <div onClick={() => setOn(!on)} style={{
        height: 60, background: "var(--sp-bg-2)", borderRadius: 12, position: "relative",
        cursor: "pointer", overflow: "hidden",
      }}>
        <div style={{
          position: "absolute", top: 10, left: on ? "calc(100% - 50px)" : 10,
          width: 40, height: 40, borderRadius: 10,
          background: "var(--sp-grad-money)",
          transition: `left ${duration} ${ease}`,
          boxShadow: "var(--sp-shadow-money)",
        }}/>
      </div>
      <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 8 }}>Tap to play</div>
    </div>
  );
}

function DSMotion() {
  return (
    <>
      <p className="sp-meta" style={{ color: "var(--sp-fg-3)", marginBottom: 24, maxWidth: 720 }}>
        Все переходы — через CSS-переменные. Длительности от quick (140ms) до anxious (900ms).
        Spring используется только для прибыли (положительный feedback), in-out — для нейтральных перемещений.
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 16 }}>
        <MotionDemo duration="140ms" ease="cubic-bezier(.2,.8,.2,1)"  label="quick · ease-out"   sub="--sp-dur-quick · hover, switch flip"/>
        <MotionDemo duration="220ms" ease="cubic-bezier(.4,0,.2,1)"   label="base · ease-in-out" sub="--sp-dur-base · sheet open, page transition"/>
        <MotionDemo duration="420ms" ease="cubic-bezier(.34,1.56,.64,1)" label="slow · spring"   sub="--sp-dur-slow · success state, +money entry"/>
        <MotionDemo duration="900ms" ease="cubic-bezier(.4,0,.2,1)"   label="anxious"            sub="--sp-dur-anxious · alarm pulse, breathing light"/>
      </div>
    </>
  );
}

/* ============================================================
   VOICE & TONE
   ============================================================ */
function DSVoice() {
  const examples = [
    { ctx: "Цена откладывания", do_: "Поспать ещё · +9 минут · 50 ₽", dont: "Доплатите 50₽ за дополнительные 9 минут лени" },
    { ctx: "Баланс пуст", do_: "Баланс пуст. Можно встать.", dont: "Внимание! У вас закончились средства!" },
    { ctx: "Streak", do_: "5 дней без откладываний · сэкономили 250 ₽", dont: "🎉 Вау! Вы молодец! Продолжайте!" },
    { ctx: "Прогрессив 4×", do_: "4-е откладывание · 200 ₽", dont: "Вы уже 4 раза не встали. Соберитесь!" },
    { ctx: "Кнопка пополнения", do_: "Пополнить · 500 ₽", dont: "Не хватает денег? Пополните счёт прямо сейчас!" },
  ];
  return (
    <>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 32 }}>
        <div style={{ background: "rgba(46,219,159,.08)", border: "1px solid rgba(46,219,159,.20)",
          borderRadius: 20, padding: 28 }}>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>Тон голоса</div>
          <div style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "12px 0" }}>Прямой, спокойный, уважающий</div>
          <ul style={{ margin: 0, paddingLeft: 18, color: "var(--sp-fg-2)", font: "var(--sp-t-body)" }}>
            <li>Нет морализаторства («соберись!», «лень!»)</li>
            <li>Нет восклицательных знаков и эмодзи в финансах</li>
            <li>Цифры до пояснений: <span style={{fontFamily:"var(--sp-font-mono)"}}>50 ₽</span> · 9 минут</li>
            <li>Глаголы в инфинитиве для CTA: «Пополнить», «Поспать ещё»</li>
          </ul>
        </div>
        <div style={{ background: "rgba(244,82,63,.08)", border: "1px solid rgba(244,82,63,.20)",
          borderRadius: 20, padding: 28 }}>
          <div className="sp-caps" style={{ color: "var(--sp-pain-400)" }}>Не делаем</div>
          <div style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "12px 0" }}>Стыд, паника, мотивашки</div>
          <ul style={{ margin: 0, paddingLeft: 18, color: "var(--sp-fg-2)", font: "var(--sp-t-body)" }}>
            <li>Не ругаем за срыв — описываем последствие</li>
            <li>Не делаем «геймифицированных» поздравлений</li>
            <li>Не маскируем списания эвфемизмами («комиссия», «активация»)</li>
            <li>Не используем !!! и капс</li>
          </ul>
        </div>
      </div>

      <h3 style={{ font: "var(--sp-t-h3)", color: "#FFF", margin: "0 0 16px" }}>Примеры</h3>
      <div style={{ background: "var(--sp-bg-1)", borderRadius: 20, border: "1px solid var(--sp-white-06)",
        overflow: "hidden" }}>
        <div style={{ display: "grid", gridTemplateColumns: "200px 1fr 1fr",
          padding: "12px 24px", borderBottom: "1px solid var(--sp-white-06)" }}>
          <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Контекст</div>
          <div className="sp-caps" style={{ color: "var(--sp-money-300)" }}>Так</div>
          <div className="sp-caps" style={{ color: "var(--sp-pain-400)" }}>Не так</div>
        </div>
        {examples.map((e, i) => (
          <div key={i} style={{ display: "grid", gridTemplateColumns: "200px 1fr 1fr",
            padding: "20px 24px", borderBottom: i < examples.length - 1 ? "1px solid var(--sp-white-06)" : 0,
            alignItems: "baseline" }}>
            <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>{e.ctx}</div>
            <div style={{ font: "var(--sp-t-body)", color: "#FFF" }}>{e.do_}</div>
            <div style={{ font: "var(--sp-t-body)", color: "var(--sp-fg-3)", textDecoration: "line-through" }}>{e.dont}</div>
          </div>
        ))}
      </div>
    </>
  );
}

/* ============================================================
   NAV
   ============================================================ */
function DSNav() {
  const items = [
    { id: "principles",  l: "Принципы" },
    { id: "colors",      l: "Цвета" },
    { id: "type",        l: "Типографика" },
    { id: "spacing",     l: "Spacing" },
    { id: "components",  l: "Компоненты" },
    { id: "icons",       l: "Иконки" },
    { id: "motion",      l: "Motion" },
    { id: "voice",       l: "Voice & Tone" },
  ];
  return (
    <nav style={{ position: "sticky", top: 0, zIndex: 10, background: "rgba(6,9,18,.90)",
      backdropFilter: "blur(16px)", borderBottom: "1px solid var(--sp-white-08)" }}>
      <div style={{ maxWidth: 1360, margin: "0 auto", padding: "16px 80px",
        display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ width: 28, height: 28, borderRadius: 8, background: "var(--sp-grad-money)",
            display: "flex", alignItems: "center", justifyContent: "center" }}>
            <IconAlarm size={16} style={{ color: "var(--sp-fg-on-money)" }}/>
          </div>
          <div style={{ font: "var(--sp-t-h4)", color: "#FFF" }}>SnoozePay DS</div>
          <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginLeft: 4 }}>v1.0</div>
        </div>
        <div style={{ display: "flex", gap: 4 }}>
          {items.map(i => (
            <a key={i.id} href={`#${i.id}`} style={{
              padding: "8px 14px", borderRadius: 10, color: "var(--sp-fg-2)",
              font: "var(--sp-t-button-sm)", textDecoration: "none",
              transition: "background var(--sp-dur-quick) var(--sp-ease-out)",
            }}>{i.l}</a>
          ))}
        </div>
      </div>
    </nav>
  );
}

/* ============================================================
   ROOT
   ============================================================ */
function DesignSystem() {
  return (
    <DSPage>
      <DSNav/>
      <DSHero/>
      <DSSection id="principles" eyebrow="01 · Foundations"
        title="Принципы"
        subtitle="Решения, к которым мы возвращаемся, когда не уверены, как поступить.">
        <DSPrinciples/>
      </DSSection>
      <DSSection id="colors" eyebrow="02 · Foundations"
        title="Цвета"
        subtitle="Три основные палитры — money, warn, pain — кодируют состояние ваших денег. Surfaces нейтральны, чтобы не конкурировать с цветом сумм.">
        <DSColors/>
      </DSSection>
      <DSSection id="type" eyebrow="03 · Foundations"
        title="Типографика"
        subtitle="Manrope для слов, JetBrains Mono для денег и времени. 16 ролей покрывают всё — от 96px-часов до 12px-капс.">
        <DSType/>
      </DSSection>
      <DSSection id="spacing" eyebrow="04 · Foundations"
        title="Spacing, радиусы, тени"
        subtitle="4px база. Цветные тени — главное элевационное решение, тени пропускают цвет CTA.">
        <DSSpacing/>
      </DSSection>
      <DSSection id="components" eyebrow="05 · Library"
        title="Компоненты"
        subtitle="13 базовых блоков. Все принимают tone-variant и size-variant, ничего больше не настраивается.">
        <DSComponents/>
      </DSSection>
      <DSSection id="icons" eyebrow="06 · Library"
        title="Иконки"
        subtitle="Lucide-style outline-семейство. 20 в стандартном наборе.">
        <DSIcons/>
      </DSSection>
      <DSSection id="motion" eyebrow="07 · Library"
        title="Motion"
        subtitle="Четыре скорости, три easing-кривые. Spring — только для положительных событий.">
        <DSMotion/>
      </DSSection>
      <DSSection id="voice" eyebrow="08 · Brand"
        title="Voice & Tone"
        subtitle="Как говорим о деньгах и сне. Прямо, без морали, без эмодзи.">
        <DSVoice/>
      </DSSection>

      <footer style={{ padding: "48px 80px", textAlign: "center", borderTop: "1px solid var(--sp-white-06)" }}>
        <div className="sp-meta" style={{ color: "var(--sp-fg-3)" }}>
          SnoozePay Design System · v1.0 · {new Date().toLocaleDateString("ru-RU")}
        </div>
      </footer>
    </DSPage>
  );
}

Object.assign(window, { DesignSystem });
