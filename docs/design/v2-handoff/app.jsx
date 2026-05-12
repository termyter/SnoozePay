// SnoozePay — главный файл документа.
// Состав: hero → 8 разделов. Полный аудит + дизайн-система.

const { useState, useMemo } = React;

/* ============================================================
   AUDIT ISSUES — заранее
   ============================================================ */
const ISSUES = [
  {
    sev: "high", area: "Брендинг / визуальный язык",
    title: "Snooze-кнопка — generic iOS Blue. Главная продуктовая идея не передаётся",
    body: [
      "Сейчас на firing-screen «Отложить (50 ₽)» отрисована стандартной системной синей кнопкой. Это бесплатное действие визуально. Цена прячется в скобках, тем же 17pt-кеглем что и слово «Отложить».",
      "Юзер платит деньги — но ни цвет, ни тип, ни размер этого не проговаривают. В 7 утра в полусне он на автомате жмёт первую большую кнопку.",
    ],
    fix: "Цена — главный объект на экране. Использовать вариант `SnoozePrice`: монотипный 32px номинал, warn-градиент (амбер) для дефолтного снуза, pain-градиент (коралл→красный) для прогрессивного. Подпись «Отложить на 5 мин» — над ценой, caps 12px, opacity .7. Под ценой — следующая стоимость («Следующий снуз: 100 ₽»). Кнопка «Я встал» — ghost, без яркого фона, чтобы не конкурировала.",
  },
  {
    sev: "high", area: "Иерархия / Wallet",
    title: "Экран пополнения — пресеты равноправны, нет якоря",
    body: [
      "Сейчас 6 одинаковых серых плиток 100/300/500/1000/2000/5000 ₽ + такая же по визуальному весу кнопка «Купить». Нет ответа на вопросы «сколько обычно достаточно?», «что выбрать?», «куда смотреть первым».",
      "Баланс — мелким текстом 30pt в сером кружке, теряется. Метрик «насколько мне этого хватит» нет вообще.",
    ],
    fix: "Hero-баланс: 56px моно, money-градиент текстом, на raised-карточке с радиальным акцентом. Под суммой — дельта за неделю и translation в сценарий («хватит на ~17 снузов при текущей цене»). Пресеты — 3×2, у одного бейдж «Популярно» (500 ₽). У каждого — meta-подпись «≈ 10 снузов». CTA приклеен к низу, sticky, со суммой в suffix-слоте.",
  },
  {
    sev: "high", area: "Доступность / контраст",
    title: "Серый текст #8E8E93 на белом #F2F2F7 — 2.7:1, ниже WCAG AA",
    body: [
      "В макетах настроек и кошелька много 13pt подписей `#8E8E93` на сером фоне `#F2F2F7`. Это 2.7:1 — провал даже для крупного текста (нужно 3:1) и тем более для мелкого (4.5:1).",
      "В тёмной теме то же самое — `rgba(235,235,245,.30)` на `#0A0F1F` это 3.1:1; используется как hint и meta — тоже фейл.",
    ],
    fix: "Минимум для meta — `rgba(235,237,245,.58)` (это `--sp-fg-3`, 7.0:1 на bg-0). Для disabled оставить .32, но disabled НЕ должен нести смысловую нагрузку — никогда не превращать важный hint в disabled-серый. Пересчитал всю шкалу: fg-1/2/3/4 = 100/86/58/32%.",
  },
  {
    sev: "high", area: "Доступность",
    title: "Hit-targets ниже 44px, текст 11pt в табах",
    body: [
      "Bottom-tab иконки в нынешних макетах ~32×32 + надпись 11pt — суммарно высота кликабельной зоны меньше 44pt iOS HIG.",
      "Switch на settings — 28pt высоты, тоже мало.",
    ],
    fix: "Все интерактивные зоны минимум 44×44pt. Tab-bar — 60pt высоты, иконка 24, лейбл 11pt 600. Switch — 32×52 (по системе уже так).",
  },
  {
    sev: "med", area: "Консистентность / spacing",
    title: "«Магические числа» в spacing — 13, 17, 22 россыпью",
    body: [
      "В Figma встречаются padding-ы 13, 17, 22, 26 — числа не из шкалы. Это обычно следы того, что дизайнер двигал блок «на глазок».",
      "В коде это превращается в десятки уникальных значений и дрожащую сетку.",
    ],
    fix: "Жёсткая шкала на базе 4: 4·8·12·16·20·24·32·40·56·72. Карточки — внутренний padding только 16 или 20. Между секциями — только 24 или 32. Никаких 13/17/22.",
  },
  {
    sev: "med", area: "Консистентность",
    title: "Карточки в light-mode «плоские» — нет ни тени, ни границы",
    body: [
      "Белая карточка на сером фоне без shadow и border читается только за счёт минимальной разницы яркости. На печати или ярком экране — почти исчезает.",
    ],
    fix: "В light: `box-shadow: 0 1px 3px rgba(8,14,30,.06), 0 4px 14px rgba(8,14,30,.06)` + опциональный hairline `rgba(10,15,31,.08)`. В dark — пусть карточка лежит на surface-step, без тени; тень добавляем только для floating элементов (FAB, modal).",
  },
  {
    sev: "med", area: "Иконография",
    title: "Иконки разной толщины и стиля — некоторые filled, некоторые stroked",
    body: [
      "В Figma часть иконок (барабан, монетка) — filled vector, часть (back, chevron) — stroke. Разная толщина, разные углы. Чтение дёрганое.",
    ],
    fix: "Единый стиль: 24×24, stroke 1.75, скругления по умолчанию, Lucide-style. Filled — только в одном случае: активная иконка на heat/money tile в табе/CTA. Один источник истины — пересобрать набор.",
  },
  {
    sev: "med", area: "Состояния",
    title: "Disabled-состояние не отличимо от enabled",
    body: [
      "Сейчас disabled-кнопка — просто чуть прозрачнее. На firing-screen где snooze заблокирован при balance=0 — пользователь не понимает, что кнопка вообще не реагирует, и долбит её.",
    ],
    fix: "Disabled = opacity .35 + grayscale(.5) + cursor not-allowed + tooltip/hint снизу «Недостаточно средств». На firing-screen вместо disabled-snooze показать explicit state: серая плитка с замком, плюс над «Я встал» появляется underline-link «Пополнить (40 ₽ хватит на 8 снузов)».",
  },
  {
    sev: "med", area: "UX / копирайтинг",
    title: "Тон заявки коммерческий, а должен быть «коучем»",
    body: [
      "«Текущий баланс», «Пополнить кошелёк», «Купить» — формулировки банковского приложения. SnoozePay — приложение про дисциплину, не про пополнение карты.",
      "На firing-screen «Отложить (50 ₽)» — нейтральная фраза. Финансовая боль не проговаривается.",
    ],
    fix: "Баланс → «Залог»/«Запас». Пополнить → «Положить под расписку». На firing-screen: «Откупиться от подъёма — 50 ₽» или «Спать ещё 5 мин · −50 ₽». На no-balance: «Залога не осталось. Только встать.» Streak-modal: «Сэкономили 350 ₽ — вернули на баланс». Голос — прямой, второе лицо, короткие фразы. Никакого «пользователь», никакого «мы поможем тебе».",
  },
  {
    sev: "low", area: "Тайпографика",
    title: "Один шрифт (Inter/Source Han) для денег и тела — деньги не отличаются",
    body: [
      "В Figma все суммы набраны тем же шрифтом, что и body. 840 ₽ читается как часть фразы, а не как ключевая цифра экрана.",
    ],
    fix: "Двухшрифтовая система: Manrope (display + body) + JetBrains Mono для всех числовых сумм и таймеров. Моно даёт tabular-nums (цифры одинаковой ширины — критично, чтобы баланс не «прыгал» при списании) и визуально отделяет деньги от текста.",
  },
  {
    sev: "low", area: "Motion",
    title: "Нет тактильности у списания — деньги уходят без события",
    body: [
      "Когда юзер жмёт snooze, баланс просто меняется со 100 на 50. Никакого ощущения «у меня списали».",
    ],
    fix: "При списании: число баланса коротко (140мс) скейлится до .96 + сдвиг -2px вверх + flash pain-цвета на 200мс, потом ease-out обратно. На балансной карточке — отметка «−50 ₽» вылетает вверх и фейдится за 600мс. Haptic.notification(.warning) на iOS. Стоит дёшево, продаёт продукт.",
  },
  {
    sev: "low", area: "Тёмная тема",
    title: "В light-mode firing-screen остаётся тёмным — это намеренно или баг?",
    body: [
      "Если автоматически переключать firing на light когда тема = light — теряется весь night-mood.",
    ],
    fix: "Намеренное исключение, задокументировать: alarm_firing_screen всегда тёмный. Это «момент пробуждения», свет должен идти снизу-сверху от системы, не от приложения. Записал в гайдлайны.",
  },
];

/* ============================================================
   THEME bar
   ============================================================ */
function ThemeBar({ theme, onChange }) {
  return (
    <div className="themebar">
      <SPSegmented
        value={theme}
        onChange={onChange}
        options={[{value:"dark", label:"Dark"},{value:"light", label:"Light"}]}
      />
    </div>
  );
}

/* ============================================================
   IssueCard
   ============================================================ */
function Issue({ data }) {
  const sevCls = `issue__sev--${data.sev}`;
  const sevLabel = { high: "Критично", med: "Средне", low: "Косметика" }[data.sev];
  return (
    <div className="issue">
      <div className="issue__head">
        <div className={`issue__sev ${sevCls}`} />
        <div style={{ flex: 1 }}>
          <div className="issue__tag">{sevLabel} · {data.area}</div>
          <div className="issue__title">{data.title}</div>
        </div>
      </div>
      <div className="issue__body">
        {data.body.map((p, i) => <p key={i}>{p}</p>)}
      </div>
      <div className="issue__fix">
        <strong>Решение</strong>
        {data.fix}
      </div>
    </div>
  );
}

/* ============================================================
   Token preview pieces
   ============================================================ */
function ColorTokens() {
  const groups = [
    { title: "Brand · сигнатура", items: [
      { name: "Money 500",  v: "--sp-money-500", hex: "#10B981", swatch: "var(--sp-money-500)" },
      { name: "Pain 500",   v: "--sp-pain-500",  hex: "#F4523F", swatch: "var(--sp-pain-500)" },
      { name: "Warn 500",   v: "--sp-warn-500",  hex: "#F59E0B", swatch: "var(--sp-warn-500)" },
      { name: "Info 500",   v: "--sp-info-500",  hex: "#4F8BFF", swatch: "var(--sp-info-500)" },
    ]},
    { title: "Surfaces · dark", items: [
      { name: "bg-0", v: "--sp-bg-0", hex: "#060912", swatch: "#060912" },
      { name: "bg-1", v: "--sp-bg-1", hex: "#0E1320", swatch: "#0E1320" },
      { name: "bg-2", v: "--sp-bg-2", hex: "#161C2E", swatch: "#161C2E" },
      { name: "bg-3", v: "--sp-bg-3", hex: "#1F2740", swatch: "#1F2740" },
    ]},
    { title: "Gradients · единственная сигнатура", items: [
      { name: "Money", v: "--sp-grad-money", hex: "→ #2EDB9F → #10B981", swatch: "var(--sp-grad-money)" },
      { name: "Pain",  v: "--sp-grad-pain",  hex: "→ #FFB4A8 → #D43A28", swatch: "var(--sp-grad-pain)" },
      { name: "Warn",  v: "--sp-grad-warn",  hex: "→ #FFD479 → #C97A06", swatch: "var(--sp-grad-warn)" },
      { name: "Dawn",  v: "--sp-grad-dawn",  hex: "vertical · 14122A → 050912", swatch: "var(--sp-grad-dawn)" },
    ]},
  ];
  return (
    <>
      {groups.map((g) => (
        <div key={g.title} style={{ marginBottom: 24 }}>
          <div className="audit__h3" style={{ marginBottom: 14 }}>{g.title}</div>
          <div className="tokens">
            {g.items.map((it) => (
              <div className="token" key={it.name}>
                <div className="token__swatch" style={{ background: it.swatch }} />
                <div className="token__name">{it.name}</div>
                <div className="token__var">{it.v}</div>
                <div className="token__hex">{it.hex}</div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </>
  );
}

function TypeScale() {
  const rows = [
    { name: "display",   sample: "7:00",                spec: "Manrope 800 · 88/92 · -.025em" },
    { name: "h1",        sample: "Стало проще встать.", spec: "Manrope 800 · 32/40" },
    { name: "h2",        sample: "Будильники",          spec: "Manrope 700 · 24/32" },
    { name: "h3",        sample: "Прогрессивный режим", spec: "Manrope 700 · 20/28" },
    { name: "body-lg",   sample: "Каждый следующий снуз — в 2 раза дороже.", spec: "Manrope 500 · 17/26" },
    { name: "body",      sample: "Покупка не возвращается, штрафы списываются с баланса.", spec: "Manrope 500 · 15/22" },
    { name: "meta",      sample: "Пятница, 27 апреля",  spec: "Manrope 500 · 13/18" },
    { name: "caps",      sample: "ВАШ ЗАЛОГ",           spec: "Manrope 700 · 12/16 · .12em" },
    { name: "money-xl",  sample: "840 ₽",               spec: "JetBrains Mono 700 · 56/60" },
    { name: "money-lg",  sample: "−50 ₽",               spec: "JetBrains Mono 700 · 32/36" },
    { name: "money-md",  sample: "100 ₽",               spec: "JetBrains Mono 700 · 20/26" },
    { name: "clock-xl",  sample: "07:00",               spec: "JetBrains Mono 200 · 96/96" },
  ];
  return (
    <div className="scale">
      {rows.map((r) => {
        const map = {
          "display": "var(--sp-t-display)",
          "h1": "var(--sp-t-h1)", "h2": "var(--sp-t-h2)", "h3": "var(--sp-t-h3)",
          "body-lg": "var(--sp-t-body-lg)", "body": "var(--sp-t-body)",
          "meta": "var(--sp-t-meta)", "caps": "var(--sp-t-caps)",
          "money-xl": "var(--sp-t-money-xl)", "money-lg": "var(--sp-t-money-lg)", "money-md": "var(--sp-t-money-md)",
          "clock-xl": "var(--sp-t-clock-xl)",
        };
        const isCaps = r.name === "caps";
        return (
          <div className="scale__row" key={r.name}>
            <div className="scale__name">{r.name}</div>
            <div className="scale__sample" style={{ font: map[r.name], color: "var(--sp-fg-1)", textTransform: isCaps ? "uppercase" : "none", letterSpacing: isCaps ? ".12em" : undefined }}>
              {r.sample}
            </div>
            <div className="scale__spec">{r.spec}</div>
          </div>
        );
      })}
    </div>
  );
}

function SpacingScale() {
  const steps = [
    {n:"sp-1", v:4}, {n:"sp-2", v:8}, {n:"sp-3", v:12}, {n:"sp-4", v:16},
    {n:"sp-5", v:20}, {n:"sp-6", v:24}, {n:"sp-7", v:32}, {n:"sp-8", v:40},
    {n:"sp-9", v:56}, {n:"sp-10", v:72},
  ];
  return (
    <div className="scale">
      {steps.map((s) => (
        <div className="scale__row" key={s.n}>
          <div className="scale__name">{s.n}</div>
          <div className="scale__sample">
            <div style={{ height: 14, width: s.v, background: "var(--sp-grad-money)", borderRadius: 4 }} />
          </div>
          <div className="scale__spec">{s.v}px</div>
        </div>
      ))}
    </div>
  );
}

/* ============================================================
   Component previews
   ============================================================ */
function ButtonsPreview() {
  return (
    <div className="preview">
      <div className="preview__head">
        <div className="preview__title">Кнопки</div>
        <div className="preview__caption">Money / Pain / Warn / Ghost / Quiet · sm/md/lg</div>
      </div>
      <div className="preview__row">
        <SPButton variant="money" size="lg" icon={<IconShield size={18}/>} suffix="500 ₽">Пополнить</SPButton>
        <SPButton variant="warn" size="lg">Отложить</SPButton>
        <SPButton variant="pain" size="lg">Удалить будильник</SPButton>
        <SPButton variant="ghost" size="lg">Я встал</SPButton>
        <SPButton variant="quiet" size="lg">Отмена</SPButton>
      </div>
      <div className="preview__row">
        <SPButton variant="money" size="md">md</SPButton>
        <SPButton variant="money" size="sm">sm</SPButton>
        <SPButton variant="money" size="md" disabled>disabled</SPButton>
      </div>
    </div>
  );
}

function CardsPreview() {
  return (
    <div className="preview">
      <div className="preview__head">
        <div className="preview__title">Карточки</div>
        <div className="preview__caption">surface · raised · money · pain · warn · outline</div>
      </div>
      <div className="preview__grid preview__grid--3">
        <SPCard tone="surface" padding={20}>
          <div className="sp-caps">Surface</div>
          <div className="sp-h3" style={{marginTop:6}}>Карточка по умолчанию</div>
        </SPCard>
        <SPCard tone="raised" padding={20}>
          <div className="sp-caps">Raised</div>
          <div className="sp-h3" style={{marginTop:6}}>Над основной</div>
        </SPCard>
        <SPCard tone="money" padding={20}>
          <div className="sp-caps" style={{color:"rgba(5,32,22,.6)"}}>Money</div>
          <div className="sp-h3" style={{marginTop:6, color:"#052016"}}>+540 ₽ за неделю</div>
        </SPCard>
        <SPCard tone="warn" padding={20}>
          <div className="sp-caps" style={{color:"rgba(26,15,0,.6)"}}>Warn</div>
          <div className="sp-h3" style={{marginTop:6, color:"#1A0F00"}}>Цена снуза 50 ₽</div>
        </SPCard>
        <SPCard tone="pain" padding={20}>
          <div className="sp-caps" style={{color:"rgba(255,255,255,.7)"}}>Pain</div>
          <div className="sp-h3" style={{marginTop:6, color:"#fff"}}>Прогрессив активен</div>
        </SPCard>
        <SPCard tone="outline" padding={20}>
          <div className="sp-caps">Outline</div>
          <div className="sp-h3" style={{marginTop:6}}>Прозрачная</div>
        </SPCard>
      </div>
    </div>
  );
}

function PillsRowsPreview() {
  return (
    <div className="preview">
      <div className="preview__head">
        <div className="preview__title">Pills · Switch · Segmented</div>
        <div className="preview__caption">Маленькие компоненты</div>
      </div>
      <div className="preview__row">
        <SPPill>50 ₽ за снуз</SPPill>
        <SPPill tone="money" icon={<IconCoin size={12}/>}>Баланс 840 ₽</SPPill>
        <SPPill tone="warn" icon={<IconCoin size={12}/>}>50 ₽</SPPill>
        <SPPill tone="pain" icon={<IconFlame size={12}/>}>Прогрессив ×4</SPPill>
      </div>
      <div className="preview__row">
        <SPSwitch checked={true} onChange={()=>{}} />
        <SPSwitch checked={false} onChange={()=>{}} />
        <SPSegmented value="dark" onChange={()=>{}} options={[{value:"dark",label:"Dark"},{value:"light",label:"Light"}]} />
      </div>
    </div>
  );
}

function SnoozePreview() {
  return (
    <div className="preview">
      <div className="preview__head">
        <div className="preview__title">Snooze price — флагман</div>
        <div className="preview__caption">Главный компонент продукта. Цена доминирует.</div>
      </div>
      <div className="preview__grid preview__grid--3">
        <SPSnoozePrice price={50} minutes={5} hint="Цена фиксированная" />
        <SPSnoozePrice price={200} minutes={5} tone="pain" hint="Следующий: 400 ₽" />
        <SPSnoozePrice price={50} minutes={5} disabled hint="Недостаточно средств" />
      </div>
    </div>
  );
}

function PresetPreview() {
  const [v, setV] = useState(500);
  return (
    <div className="preview">
      <div className="preview__head">
        <div className="preview__title">Amount preset</div>
        <div className="preview__caption">Сетка 3×2 на экране кошелька</div>
      </div>
      <div className="preview__grid preview__grid--3" style={{ paddingTop: 12 }}>
        <SPAmountPreset value={100}  label="≈ 2 снуза" selected={v===100} onClick={()=>setV(100)} />
        <SPAmountPreset value={500}  label="≈ 10 снузов" popular selected={v===500} onClick={()=>setV(500)} />
        <SPAmountPreset value={1000} label="≈ 20 снузов" selected={v===1000} onClick={()=>setV(1000)} />
      </div>
    </div>
  );
}

/* ============================================================
   Before/After block
   ============================================================ */
function BA({ title, before, after, beforeNotes, afterNotes }) {
  return (
    <div>
      <div className="audit__h3" style={{ marginBottom: 24 }}>{title}</div>
      <div className="ba">
        <div className="ba__col">
          <div className="ba__label ba__label--before">
            <span className="ba__dot ba__dot--before" />
            BEFORE — текущие проблемы
          </div>
          <div className="phone"><div className="phone__notch"/>{before}<div className="phone__home"/></div>
          <div className="ba__notes ba__notes--before">
            <ul>{beforeNotes.map((n,i) => <li key={i}>{n}</li>)}</ul>
          </div>
        </div>
        <div className="ba__col">
          <div className="ba__label ba__label--after">
            <span className="ba__dot ba__dot--after" />
            AFTER — фикс по системе
          </div>
          <div className="phone"><div className="phone__notch"/>{after}<div className="phone__home"/></div>
          <div className="ba__notes">
            <ul>{afterNotes.map((n,i) => <li key={i}>{n}</li>)}</ul>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   APP
   ============================================================ */
function App() {
  const sectionsTOC = [
    ["#summary",     "Резюме"],
    ["#issues",      "Аудит — 12 проблем"],
    ["#tokens",      "Токены"],
    ["#components",  "Компоненты"],
    ["#screens",     "Экраны · before/after"],
    ["#guidelines",  "Гайдлайны"],
    ["#next",        "Что дальше"],
  ];

  return (
    <div className="doc">
      <div className="audit">
        {/* HERO */}
        <div className="audit__hero">
          <div className="audit__kicker">SnoozePay · Дизайн-аудит и система · v0.1 · апрель 2026</div>
          <h1 className="audit__h1">Будильник, который стоит денег — должен это показывать.</h1>
          <div className="audit__lead">
            Прошёл по всем 17 фреймам в Figma. Нашёл 12 проблем — от провала контраста до того, что главная продуктовая
            идея (цена снуза) визуально не существует. Ниже — что не так, как чинить, и собранная под SnoozePay
            дизайн-система: токены, 14 компонентов, 5 фикснутых экранов в обеих темах.
          </div>
          <div className="audit__meta">
            <div>Платформа<strong>iOS · 393×852</strong></div>
            <div>Темы<strong>Dark + Light</strong></div>
            <div>База<strong>Protrainer DS, адаптировано</strong></div>
            <div>Проблем<strong><span style={{color:"var(--sp-pain-400)"}}>4 крит</span> · <span style={{color:"var(--sp-warn-400)"}}>5 ср</span> · <span style={{color:"var(--sp-money-400)"}}>3 косм</span></strong></div>
          </div>
        </div>

        <div className="layout">
          <div>
            {/* SUMMARY */}
            <div id="summary">
              <div className="audit__sectionTitle">
                <span className="audit__num">01</span>
                <h2 className="audit__h2">Главные выводы</h2>
              </div>
              <div className="audit__sub">
                Если коротко — что нужно фиксить в первую очередь, без воды.
              </div>
              <div className="gl-grid">
                <div className="gl-dont">
                  <strong>Что больше всего болит</strong>
                  <p>1. Snooze-кнопка не отличается от любой iOS CTA. Цена не доминирует — продукт не понятен.</p>
                  <p>2. Wallet — равноправная сетка пресетов без якоря. Юзер не знает, что выбрать.</p>
                  <p>3. Контраст серых meta-текстов проваливает WCAG AA — и в light, и в dark.</p>
                  <p>4. Тон — банковский. SnoozePay — про дисциплину, а не про пополнение карты.</p>
                </div>
                <div className="gl-do">
                  <strong>Что меняется в системе</strong>
                  <p>1. Цена снуза — отдельный компонент `SnoozePrice` с моно-шрифтом и warn/pain градиентом. Доминирует на экране.</p>
                  <p>2. Hero-баланс с money-градиентом + пресеты с meta-подписью «≈ N снузов» + бейдж «Популярно».</p>
                  <p>3. Контрастная шкала fg-1/2/3/4 = 100/86/58/32%. Все meta — выше .58.</p>
                  <p>4. Голос: «Залог», «Откупиться от подъёма», «Сэкономили 350 ₽». Прямой, второе лицо.</p>
                </div>
              </div>
            </div>

            {/* ISSUES */}
            <div id="issues">
              <div className="audit__sectionTitle">
                <span className="audit__num">02</span>
                <h2 className="audit__h2">12 проблем — детально</h2>
              </div>
              <div className="audit__sub">
                Отсортированы по тяжести: критичные → средние → косметика.
                У каждой — наблюдение и конкретный фикс.
              </div>
              {ISSUES.map((iss, i) => <Issue key={i} data={iss} />)}
            </div>

            {/* TOKENS */}
            <div id="tokens">
              <div className="audit__sectionTitle">
                <span className="audit__num">03</span>
                <h2 className="audit__h2">Токены</h2>
              </div>
              <div className="audit__sub">
                Один сигнатурный градиент (money), два поддерживающих (pain, warn). Surface-лестница 5 ступеней.
                Текст — через альфа-белые, чтобы не плодить отдельные цвета на каждый surface.
              </div>
              <ColorTokens />
              <div className="audit__h3" style={{ margin: "32px 0 14px" }}>Тип-шкала</div>
              <TypeScale />
              <div className="audit__h3" style={{ margin: "32px 0 14px" }}>Spacing — 4px база</div>
              <SpacingScale />
            </div>

            {/* COMPONENTS */}
            <div id="components">
              <div className="audit__sectionTitle">
                <span className="audit__num">04</span>
                <h2 className="audit__h2">Компоненты</h2>
              </div>
              <div className="audit__sub">
                14 компонентов. Подсвечены те, что специфичны для SnoozePay — `SnoozePrice` и `BalanceCard`.
              </div>
              <ButtonsPreview />
              <CardsPreview />
              <SnoozePreview />
              <PresetPreview />
              <PillsRowsPreview />
            </div>

            {/* SCREENS */}
            <div id="screens">
              <div className="audit__sectionTitle">
                <span className="audit__num">05</span>
                <h2 className="audit__h2">Экраны · before / after</h2>
              </div>
              <div className="audit__sub">
                Слева — реконструкция нынешнего макета с типичными проблемами. Справа — фикс по новой системе.
              </div>

              <BA
                title="Alarm Firing — обычный снуз"
                before={<FiringBefore />}
                after={<FiringAfter />}
                beforeNotes={[
                  "Generic iOS Blue для snooze — продукт визуально не существует.",
                  "Цена 50 ₽ в скобках, тем же шрифтом — не выделена.",
                  "Дата и слово «Будильник» дублируют статус-бар без новой информации.",
                  "Нет индикации баланса — сколько осталось снузов?",
                ]}
                afterNotes={[
                  "Время — clock-xl 96px, моно, tabular-nums. Никаких прыжков цифр.",
                  "Цена снуза — отдельный warn-компонент. Это не «кнопка», это «штраф».",
                  "Под ценой — hint о следующем снузе (тут «Цена фиксированная»).",
                  "Баланс виден pill-ом сверху. «Я встал» — ghost, чтобы не конкурировать визуально.",
                ]}
              />

              <BA
                title="Alarm Firing — прогрессивный режим"
                before={<FiringBefore />}
                after={<FiringAfter progressive />}
                beforeNotes={[
                  "В нынешних макетах прогрессивный режим визуально не отличается от обычного.",
                  "Юзер не помнит, что вчера снуз стоил 50 ₽, а сегодня 200 — нет напоминания.",
                ]}
                afterNotes={[
                  "Pain-градиент на цене — коралл→красный. Цвет = тревога.",
                  "Pill «Прогрессив ×4» рядом с балансом — чёткое напоминание режима.",
                  "Hint «Следующий снуз: 400 ₽» — экономика на экране.",
                ]}
              />

              <BA
                title="Alarm Firing — баланс закончился"
                before={<FiringBefore />}
                after={<FiringNoBalance />}
                beforeNotes={[
                  "В нынешних макетах нет специального состояния для balance=0.",
                  "Если просто заблокировать кнопку — юзер долбит её и злится.",
                ]}
                afterNotes={[
                  "Snooze явно disabled с подписью «Недостаточно средств».",
                  "Pill баланса в pain-цвете — «Баланс 0 ₽».",
                  "«Я встал» становится primary money-кнопкой — единственный путь дальше.",
                  "Текст: «Откладывать больше не получится. Только встать.» — прямо и без морализаторства.",
                ]}
              />

              <BA
                title="Wallet / Deposit — иерархия и якорь"
                before={<WalletBefore />}
                after={<WalletAfter />}
                beforeNotes={[
                  "Все 6 пресетов одинакового веса — «куда смотреть?».",
                  "Баланс мелкий, без контекста («хватит на сколько?»).",
                  "Кнопка «Купить» такая же синяя, как пресеты — не выделена.",
                  "Контраст meta-текста #8E8E93 на #F2F2F7 = 2.7:1 — провал WCAG.",
                ]}
                afterNotes={[
                  "Hero-balance 56pt моно с money-градиентом. Дельта за неделю и translation в сценарий.",
                  "Один пресет с бейджем «Популярно» — якорь. Под каждым meta «≈ N снузов».",
                  "CTA приклеен к низу, со суммой в suffix. Apple Pay — primary money.",
                  "Disclaimer внизу: «покупка не возвращается» — раз и явно, не миллион раз.",
                ]}
              />

              <BA
                title="Список будильников"
                before={<FiringBefore />}
                after={<AlarmsListAfter />}
                beforeNotes={[
                  "Нет специального экрана списка в Figma — пустой стейт продукта.",
                ]}
                afterNotes={[
                  "Каждая карточка несёт всю экономику будильника: время, цена снуза, прогрессив, звук.",
                  "Активный — raised, выключенный — surface + opacity на цифре.",
                  "Tab-bar 3 вкладки: Будильники / Кошелёк / Статистика. Активная — money-цвет.",
                ]}
              />

              <BA
                title="Создание будильника"
                before={<FiringBefore />}
                after={<CreateAlarmAfter />}
                beforeNotes={[
                  "В нынешних макетах cost-настройка спрятана глубоко — она кажется опцией, а не сутью.",
                ]}
                afterNotes={[
                  "Time-picker 96pt — главный объект. Список настроек ниже — обычные rows.",
                  "«Цена снуза» — собственная row с warn-цветом цифры и подсказкой.",
                  "Прогрессив — отдельная карта с pain-stroke. Подробное описание во второй строчке: «50 → 100 → 200 → 400 ₽».",
                ]}
              />

              <BA
                title="Streak modal — позитивное подкрепление"
                before={<FiringBefore />}
                after={<StreakModal />}
                beforeNotes={[
                  "Нет компонента positive-feedback в Figma. Юзер не получает дофамина за дисциплину.",
                ]}
                afterNotes={[
                  "Модалка снизу с money-tile иконкой пламени.",
                  "Цифра «350 ₽» — звезда экрана. «Сэкономили» — глагол достижения.",
                  "CTA «Поделиться» — viral-loop. «Закрыть» — quiet, чтобы не отвлекать.",
                ]}
              />
            </div>

            {/* GUIDELINES */}
            <div id="guidelines">
              <div className="audit__sectionTitle">
                <span className="audit__num">06</span>
                <h2 className="audit__h2">Гайдлайны</h2>
              </div>
              <div className="audit__sub">
                Принципы, которыми должна руководствоваться команда при добавлении новых экранов.
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>Цвет</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>Money-градиент только на одном элементе экрана: либо primary CTA, либо hero-сумма. Не оба.</p>
                  <p>Pain — только когда это про потерю денег или удаление. Не для общего «alert».</p>
                  <p>Warn — для цены снуза по умолчанию. Это «осторожно», не «опасно».</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Не использовать 3 градиента на одном экране. Один сигнатурный + остальное surface.</p>
                  <p>Не делать info-синие кнопки рядом с money-зелёными — будут конкурировать.</p>
                  <p>Не делать pain-градиент на «Удалить» если можно undo. Это про необратимое.</p>
                </div>
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>Тайпографика и числа</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>Все суммы и таймеры — JetBrains Mono с tabular-nums. Никаких прыжков цифр при изменении баланса.</p>
                  <p>Минус перед суммой: −50 ₽. Плюс не пишем (default — позитив).</p>
                  <p>Caps только для коротких eyebrow (≤24 символа). Не для предложений.</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Не набирать суммы шрифтом тела. Деньги должны выглядеть как деньги.</p>
                  <p>Не использовать лёгкие веса (200) для чего-либо, кроме clock-xl.</p>
                  <p>Не писать суммы прописью — «50 рублей» вместо «50 ₽». Сжатость важна.</p>
                </div>
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>Тёмная тема</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>Surface-лестница bg-0 → bg-4 от parent к child. Карточка всегда на ступень выше окружения.</p>
                  <p>Тени — цветные. На money — money-glow, на pain — pain-glow. Никогда чёрный shadow на тёмном фоне.</p>
                  <p>Alarm firing screen остаётся тёмным даже если system-theme = light. Это «момент пробуждения».</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Не делать прозрачные стеклянные карточки везде. Это путает иерархию.</p>
                  <p>Не использовать чисто чёрный (#000) — глаза устают. Bg-0 = #060912.</p>
                  <p>Не ставить border-1px на каждую карточку — surface-step делает всю работу.</p>
                </div>
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>UX и копирайтинг</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>«Залог» вместо «Баланс». «Залог» подразумевает — это твои деньги под расписку.</p>
                  <p>«Откупиться от подъёма» вместо «Отложить». Прямое имя действия.</p>
                  <p>Streak: глаголы достижения — «Сэкономили», «Удержался 7 дней».</p>
                  <p>На no-balance: «Залога не осталось. Только встать.» — без морализаторства.</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Никакого «пользователь» — только «ты»/2-е лицо.</p>
                  <p>Не оправдывать списания. «Спишется 50 ₽» — без «к сожалению» и «обратите внимание».</p>
                  <p>Не использовать эмодзи в основном UI. Только в pill-ах для experience-level или mood (если будут).</p>
                  <p>Не превращать alarm-firing в коуч-приложение. Это будильник, не motivation app.</p>
                </div>
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>Состояния (hover / press / disabled / focus)</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>Press: scale(.97) на CTA, без изменения цвета. Тактильно, не визуально шумно.</p>
                  <p>Hover: translateY(-1px) + усиление shadow на 1 ступень. Только desktop.</p>
                  <p>Disabled: opacity .35 + grayscale(.5) + cursor not-allowed + текстовая подсказка ПОЧЕМУ.</p>
                  <p>Focus: heat-ring rgba(46,219,159,.55) с halo .12α 4px.</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Не убирать focus-ring. Клавиатурная навигация — обязательна.</p>
                  <p>Не делать disabled молчаливым. Если кнопка не работает — пиши почему рядом.</p>
                  <p>Не анимировать hover на тач-устройствах (`@media (hover:hover)`).</p>
                </div>
              </div>

              <div className="audit__h3" style={{ marginTop: 32 }}>Motion</div>
              <div className="gl-grid">
                <div className="gl-do">
                  <strong>DO</strong>
                  <p>Списание баланса: счётчик scale(.96) + flash pain + ease-out обратно за 220мс. Haptic.warning.</p>
                  <p>Streak-модалка: появляется снизу spring-easing, иконка pulse 1 раз.</p>
                  <p>Firing: пульсация цены snooze 900мс — спокойная, не агрессивная.</p>
                </div>
                <div className="gl-dont">
                  <strong>DON'T</strong>
                  <p>Никакого bouncy-easing на UI. Spring — только на celebrations и FAB.</p>
                  <p>Никаких «прыгающих цифр» баланса. Tabular-nums + numberFlow.</p>
                  <p>Не анимировать всё подряд. Motion — для смыслонесущих событий.</p>
                </div>
              </div>
            </div>

            {/* NEXT */}
            <div id="next">
              <div className="audit__sectionTitle">
                <span className="audit__num">07</span>
                <h2 className="audit__h2">Что дальше</h2>
              </div>
              <div className="audit__sub">
                Этот документ — стартовая точка. Что докручивать в следующих итерациях.
              </div>
              <SPCard tone="raised" padding={28} radius={20}>
                <ul style={{ margin: 0, paddingLeft: 20, font: "var(--sp-t-body-lg)", color: "var(--sp-fg-2)" }}>
                  <li style={{ marginBottom: 10 }}>Экран статистики — графики «потрачено за неделю», «снузов в день», «лучшая серия». Сейчас белое пятно.</li>
                  <li style={{ marginBottom: 10 }}>Onboarding — 3 экрана: «Что такое SnoozePay» / «Как это работает» / «Положи первый залог». Без него штрафы выглядят как баг.</li>
                  <li style={{ marginBottom: 10 }}>Empty states — нет будильников, история пуста, статистики ещё нет. Сейчас не нарисованы.</li>
                  <li style={{ marginBottom: 10 }}>Charity-режим из v2 — конкретные организации с логотипами, объяснение «как это работает». Может стать главным маркетинговым крючком.</li>
                  <li style={{ marginBottom: 10 }}>Пересмотреть нейминг продукта на экране настроек — «Снуз», «Залог», «Прогрессив» — нужен mini-glossary в первом онбординге.</li>
                  <li>Иконки — заменить нынешний микс на единый набор (Lucide или собственный) и зафиксировать в репо.</li>
                </ul>
              </SPCard>
            </div>
          </div>

          <nav className="toc">
            <div className="toc__title">Содержание</div>
            <div className="toc__list">
              {sectionsTOC.map(([h, l]) => (
                <a className="toc__item" href={h} key={h}>{l}</a>
              ))}
            </div>
          </nav>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
