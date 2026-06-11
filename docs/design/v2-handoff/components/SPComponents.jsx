// SnoozePay — UI primitives.
// Все компоненты — в edge-стиле Protrainer DS, адаптировано.
// Экспортируются в window для других babel-скриптов.

const { useState, useEffect, useRef, useMemo } = React;

/* ───── helpers ───── */
const cx = (...xs) => xs.filter(Boolean).join(" ");
/*  Money rendering — tabular-nums ONLY on the digit run so the space character
    keeps its normal proportional width (~4dp). Container can still be tabular for
    column alignment; the inner spans override at the digit/symbol level.        */
const fmtRubDigits = (n) => Math.round(n).toLocaleString("ru-RU");
const fmtRub = (n) => (
  <>
    <span style={{ fontVariantNumeric: "tabular-nums" }}>{fmtRubDigits(n)}</span>
    {/* Space rendered in body (proportional) font so the gap is ~4dp instead of
        JetBrains Mono's full-cell ~12dp. Hair-thin span, just for the space. */}
    <span style={{ fontFamily: "var(--sp-font-body)", fontVariantNumeric: "normal" }}>{" "}</span>
    <span>₽</span>
  </>
);
/* String form — for template literals / aria labels where JSX can't render. */
const fmtRubStr = (n) => `${fmtRubDigits(n)} ₽`;
const fmtRubTight = fmtRub;

/* ============================================================
   SPButton
   variant: money (primary CTA, деньги) | pain (стоп, удалить, прогрессив)
            warn (snooze) | ghost | quiet
   size: lg (56) | md (48) | sm (36)
   ============================================================ */
function SPButton({ children, variant = "money", size = "lg", icon, suffix, full, disabled, onClick, style }) {
  const cls = cx(
    "sp-btn",
    `sp-btn--${variant}`,
    `sp-btn--${size}`,
    full && "sp-btn--full",
    disabled && "is-disabled"
  );
  return (
    <button className={cls} disabled={disabled} onClick={onClick} style={style}>
      {icon && <span className="sp-btn__icon">{icon}</span>}
      <span className="sp-btn__label">{children}</span>
      {suffix && <span className="sp-btn__suffix">{suffix}</span>}
    </button>);

}

/* ============================================================
   SPCard — основная карточка
   tone: surface | raised | money | pain | warn | outline
   ============================================================ */
function SPCard({ children, tone = "surface", padding = 20, radius, style, onClick }) {
  return (
    <div
      className={cx("sp-card", `sp-card--${tone}`, onClick && "sp-card--interactive")}
      style={{ padding, borderRadius: radius, ...style }}
      onClick={onClick}>
      
      {children}
    </div>);

}

/* ============================================================
   SPPill — бейдж/чип
   ============================================================ */
function SPPill({ children, tone = "neutral", icon }) {
  return (
    <span className={cx("sp-pill", `sp-pill--${tone}`)}>
      {icon && <span className="sp-pill__icon">{icon}</span>}
      {children}
    </span>);

}

/* ============================================================
   SPRow — строка списка / settings row
   ============================================================ */
function SPRow({ leading, title, subtitle, trailing, onClick, divider = true }) {
  return (
    <div className={cx("sp-row", divider && "sp-row--divider", onClick && "sp-row--interactive")} onClick={onClick}>
      {leading && <div className="sp-row__leading">{leading}</div>}
      <div className="sp-row__main">
        <div className="sp-row__title">{title}</div>
        {subtitle && <div className="sp-row__subtitle">{subtitle}</div>}
      </div>
      {trailing && <div className="sp-row__trailing">{trailing}</div>}
    </div>);

}

/* ============================================================
   SPAmountPreset — карточка пресета суммы пополнения
   Большой моно-шрифт, явная иерархия.
   ============================================================ */
function SPAmountPreset({ value, label, selected, popular, onClick }) {
  return (
    <button
      className={cx("sp-preset", selected && "is-selected", popular && "is-popular")}
      onClick={onClick}>
      
      {popular && <span className="sp-preset__pop">Популярно</span>}
      <span className="sp-preset__value">{fmtRub(value)}</span>
      {label && <span className="sp-preset__label">{label}</span>}
    </button>);

}

/* ============================================================
   SPSnoozePrice — большая кнопка откладывания с ценой
   tone: warn (обычная) | pain (прогрессивная, дорогая)
   ============================================================ */
function SPSnoozePrice({ price, minutes = 5, tone = "warn", onClick, disabled, hint }) {
  return (
    <button
      className={cx("sp-snooze", `sp-snooze--${tone}`, disabled && "is-disabled")}
      onClick={onClick}
      disabled={disabled}>
      
      <div className="sp-snooze__top">
        <span className="sp-snooze__caps">Отложить на {minutes} мин</span>
      </div>
      <div className="sp-snooze__price">−{fmtRub(price)}</div>
      {hint && <div className="sp-snooze__hint">{hint}</div>}
    </button>);

}

/* ============================================================
   SPBalanceCard — герой-карточка с балансом
   ============================================================ */
function SPBalanceCard({ balance, delta, hint }) {
  return (
    <div className="sp-balance">
      <div className="sp-balance__caps" style={{ fontSize: "18px" }}>Баланс</div>
      <div className="sp-balance__value">{fmtRub(balance)}</div>
      {delta !== undefined &&
      <div className={cx("sp-balance__delta", delta < 0 ? "is-down" : "is-up")}>
          {delta < 0 ? "↓" : "↑"} {fmtRub(Math.abs(delta))} за неделю
        </div>
      }
      {hint && <div className="sp-balance__hint">{hint}</div>}
    </div>);

}

/* ============================================================
   SnoozePriceCard — inline editable snooze price.
   Large mono numeric input + ₽ suffix, with quick-fill chips below.
   Out-of-bounds (10..500) shows red helper text.
   Used on screens 08 (Create alarm) and 10 (Edit alarm) — single source of
   truth so the two screens stay in lockstep.
   ============================================================ */
function SnoozePriceCard({ value, onChange, min = 1, max = Infinity, presets = [20, 50, 100, 200, 500] }) {
  const oob = value < min || value > max;
  const accent = oob ? "var(--sp-pain-400)" : "var(--sp-warn-400)";
  return (
    <SPCard padding={20} radius={20}>
      <div className="sp-caps" style={{ color: "var(--sp-fg-3)" }}>Цена откладывания</div>
      <div className="sp-meta" style={{ color: "var(--sp-fg-3)", marginTop: 2 }}>
        Сколько спишется при «отложить»
      </div>
      {/* Editable numeric input — money-lg (32px), not money-xl (56px).
          Big enough to feel like the editable focal element of the card,
          but not so big it dominates the screen above other controls.
          ₽ inherits the same accent as the digits so the value reads as one unit. */}
      <div style={{ display: "flex", alignItems: "baseline", marginTop: 12, gap: 4 }}>
        <input
          type="text"
          inputMode="numeric"
          pattern="[0-9]*"
          value={value}
          onChange={(e) => {
            const n = parseInt(e.target.value.replace(/\D+/g, ""), 10);
            onChange(Number.isFinite(n) ? n : 0);
          }}
          style={{
            background: "transparent", border: 0, outline: "none",
            color: accent,
            caretColor: accent,
            font: "var(--sp-t-money-lg)",
            letterSpacing: "-.01em",
            fontVariantNumeric: "tabular-nums",
            width: "auto", minWidth: 0, maxWidth: 140,
            fieldSizing: "content",
            padding: 0,
          }}
        />
        <span style={{ font: "var(--sp-t-money-lg)", color: accent }}>₽</span>
      </div>
      {oob && (
        <div className="sp-meta" style={{ color: "var(--sp-pain-400)", marginTop: 4 }}>
          Минимум {fmtRub(min)}
        </div>
      )}
      {/* Quick-fill chips. Shortcut, not selection state — but the matching
          chip gets a subtle accent so the user sees what they tapped. */}
      <div style={{ display: "flex", gap: 8, marginTop: 16, flexWrap: "wrap" }}>
        {presets.map((p) => {
          const on = value === p;
          return (
            <button key={p} onClick={() => onChange(p)} style={{
              padding: "6px 12px", borderRadius: 999, border: 0, cursor: "pointer",
              background: on ? "rgba(245,158,11,.14)" : "var(--sp-white-06)",
              color: on ? "var(--sp-warn-300)" : "var(--sp-fg-2)",
              font: "var(--sp-t-button-sm)",
              fontFamily: "var(--sp-font-mono)",
            }}>{p}</button>
          );
        })}
      </div>
    </SPCard>
  );
}

/* ============================================================
   SPSegmented — segmented control
   ============================================================ */
function SPSegmented({ options, value, onChange }) {
  return (
    <div className="sp-seg" role="tablist">
      {options.map((o) =>
      <button
        key={o.value}
        role="tab"
        aria-selected={value === o.value}
        className={cx("sp-seg__opt", value === o.value && "is-on")}
        onClick={() => onChange?.(o.value)}>
        
          {o.label}
        </button>
      )}
    </div>);

}

/* ============================================================
   SPSwitch — toggle
   ============================================================ */
function SPSwitch({ checked, onChange, disabled }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      className={cx("sp-switch", checked && "is-on", disabled && "is-disabled")}
      disabled={disabled}
      onClick={() => !disabled && onChange?.(!checked)}>
      
      <span className="sp-switch__knob" />
    </button>);

}

/* ============================================================
   SPStatusBar — fake iOS статус-бар
   ============================================================ */
function SPStatusBar({ time = "7:00", tone = "light" }) {
  const isDark = tone === "dark";
  const c = isDark ? "#0A0F1F" : "#FFFFFF";
  return (
    <div className="sp-statusbar" style={{ color: c }}>
      <span className="sp-statusbar__time">{time}</span>
      <div className="sp-statusbar__icons">
        <svg width="18" height="11" viewBox="0 0 18 11" fill="none">
          <path d="M1 8 L1.5 7 L1 6 Z M4 9 L4.5 7 L4 5 Z M7 10 L7.5 7 L7 4 Z M10 11 L10.5 7 L10 3 Z" stroke={c} strokeWidth="1.6" fill={c} />
        </svg>
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none">
          <path d="M8 3 C5 3 3 5 1 7 M8 5 C6 5 4 6 3 8 M8 8 L8.5 9 L8 10 L7.5 9 Z" stroke={c} strokeWidth="1.4" fill="none" />
        </svg>
        <svg width="26" height="11" viewBox="0 0 26 11" fill="none">
          <rect x="1" y="1" width="22" height="9" rx="2" stroke={c} strokeOpacity=".5" strokeWidth="1" fill="none" />
          <rect x="3" y="3" width="16" height="5" rx="1" fill={c} />
          <rect x="24" y="4" width="1.5" height="3" rx=".5" fill={c} fillOpacity=".5" />
        </svg>
      </div>
    </div>);

}

/* ============================================================
   SPNavBar — top nav
   ============================================================ */
function SPNavBar({ title, leading, trailing, large }) {
  return (
    <div className={cx("sp-navbar", large && "sp-navbar--large")}>
      <div className="sp-navbar__row">
        <div className="sp-navbar__leading">{leading}</div>
        {!large && <div className="sp-navbar__title">{title}</div>}
        <div className="sp-navbar__trailing">{trailing}</div>
      </div>
      {large && <div className="sp-navbar__largeTitle">{title}</div>}
    </div>);

}

/* ============================================================
   SPTabBar — bottom tab bar (3 вкладки SnoozePay)
   ============================================================ */
function SPTabBar({ active = "alarms", onTab }) {
  const tabs = [
  { id: "alarms", label: "Будильники", icon: <IconAlarm /> },
  { id: "wallet", label: "Кошелёк", icon: <IconWallet /> },
  { id: "stats", label: "Статистика", icon: <IconStats /> }];

  return (
    <div className="sp-tabbar">
      {tabs.map((t) =>
      <button
        key={t.id}
        className={cx("sp-tabbar__tab", active === t.id && "is-on")}
        onClick={() => onTab?.(t.id)}>
        
          <span className="sp-tabbar__icon">{t.icon}</span>
          <span className="sp-tabbar__label">{t.label}</span>
        </button>
      )}
    </div>);

}

/* ============================================================
   SPInput
   ============================================================ */
function SPInput({ label, value, onChange, placeholder, type = "text", trailing, error, hint }) {
  return (
    <label className={cx("sp-input", error && "is-error")}>
      {label && <span className="sp-input__label">{label}</span>}
      <span className="sp-input__field">
        <input
          type={type}
          value={value}
          onChange={(e) => onChange?.(e.target.value)}
          placeholder={placeholder} />
        
        {trailing && <span className="sp-input__trailing">{trailing}</span>}
      </span>
      {error ? <span className="sp-input__hint is-err">{error}</span> :
      hint && <span className="sp-input__hint">{hint}</span>}
    </label>);

}

/* ============================================================
   ICONS (24×24, 1.75 stroke, Lucide-style)
   ============================================================ */
const Ico = ({ children, size = 24, ...rest }) =>
<svg width={size} height={size} viewBox="0 0 24 24" fill="none"
stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" {...rest}>
    {children}
  </svg>;

const IconAlarm = (p) => <Ico {...p}><circle cx="12" cy="13" r="8" /><path d="M12 9v4l2 2" /><path d="M5 4l-2 2M19 4l2 2" /></Ico>;
const IconWallet = (p) => <Ico {...p}><rect x="3" y="6" width="18" height="14" rx="3" /><path d="M3 10h18M16 14h2" /><path d="M18 6V4a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v2" /></Ico>;
const IconStats = (p) => <Ico {...p}><path d="M3 20h18" /><rect x="6" y="11" width="3" height="6" rx="1" /><rect x="11" y="7" width="3" height="10" rx="1" /><rect x="16" y="13" width="3" height="4" rx="1" /></Ico>;
const IconPlus = (p) => <Ico {...p}><path d="M12 5v14M5 12h14" /></Ico>;
const IconBack = (p) => <Ico {...p}><path d="M15 6l-6 6 6 6" /></Ico>;
const IconClose = (p) => <Ico {...p}><path d="M6 6l12 12M18 6L6 18" /></Ico>;
const IconCheck = (p) => <Ico {...p}><path d="M5 12l5 5L20 7" /></Ico>;
const IconChevR = (p) => <Ico {...p}><path d="M9 6l6 6-6 6" /></Ico>;
const IconBell = (p) => <Ico {...p}><path d="M6 19V11a6 6 0 0 1 12 0v8" /><path d="M4 19h16" /><path d="M10 22h4" /></Ico>;
const IconFlame = (p) => <Ico {...p}><path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-3 2-4 2-7 1 2 3 2 3-3z" /></Ico>;
// Монета с ₽ — единый icon для всех money/balance индикаторов.
// Круг + чистый символ рубля внутри. Цвет наследуется по currentColor.
const IconCoin = (p) =>
<Ico {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M9 8v9" />
    <path d="M9 8h3.5a2.5 2.5 0 0 1 0 5H9" />
    <path d="M7.5 14.5H13" />
  </Ico>;

// Монета с ₽ + диагональный слэш — «нет денег». Тот же глиф, перечёркнутый.
const IconCoinOff = (p) =>
<Ico {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M9 8v9" />
    <path d="M9 8h3.5a2.5 2.5 0 0 1 0 5H9" />
    <path d="M7.5 14.5H13" />
    <path d="M4.5 4.5l15 15" />
  </Ico>;

const IconArrowDn = (p) => <Ico {...p}><path d="M12 5v14M6 13l6 6 6-6" /></Ico>;
const IconArrowUp = (p) => <Ico {...p}><path d="M12 19V5M6 11l6-6 6 6" /></Ico>;
const IconShield = (p) => <Ico {...p}><path d="M12 3l8 4v6c0 4-3 7-8 8-5-1-8-4-8-8V7l8-4z" /></Ico>;
const IconSound = (p) => <Ico {...p}><path d="M11 5L6 9H3v6h3l5 4V5z" /><path d="M16 9a4 4 0 0 1 0 6" /><path d="M19 6a8 8 0 0 1 0 12" /></Ico>;
const IconChart = (p) => <Ico {...p}><path d="M3 17l5-5 4 4 8-9" /></Ico>;
const IconTrash = (p) => <Ico {...p}><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13" /></Ico>;
const IconClock = (p) => <Ico {...p}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></Ico>;
const IconUser = (p) => <Ico {...p}><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4 4-7 8-7s8 3 8 7" /></Ico>;
const IconLock = (p) => <Ico {...p}><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></Ico>;
/* Gear — Lucide-style settings cog. Central circle + 8 teeth. */
const IconSettings = (p) =>
<Ico {...p}>
  <circle cx="12" cy="12" r="3" />
  <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
</Ico>;
/* Battery — горизонтальная батарейка с тонким контактом справа. */
const IconBattery = (p) =>
<Ico {...p}>
  <rect x="2" y="8" width="18" height="10" rx="2" />
  <path d="M22 11v2" />
  <path d="M5 11v4M8 11v4M11 11v4" />
</Ico>;
/* Lock-screen — экран телефона с замком по центру. */
const IconLockScreen = (p) =>
<Ico {...p}>
  <rect x="5" y="2" width="14" height="20" rx="3" />
  <rect x="9" y="11" width="6" height="5" rx="1" />
  <path d="M10.5 11V9.5a1.5 1.5 0 0 1 3 0V11" />
</Ico>;
// «Zz» — снуз. Большая Z + маленькая Z, по диагонали. Читается мгновенно.
const IconSnooze = (p) =>
<Ico {...p}>
    <path d="M13 5h6l-6 8h6" />
    <path d="M5 13h4l-4 5h4" />
  </Ico>;

// Монета с ₽ — круг + чистый символ рубля внутри. Читается как «деньги/цена».
const IconRubleCoin = (p) =>
<Ico {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M9 8v9" />
    <path d="M9 8h3.5a2.5 2.5 0 0 1 0 5H9" />
    <path d="M7.5 14.5H13" />
  </Ico>;

// Купюра с ₽ — деньги/цена. Прямоугольник + символ рубля внутри читается как «деньги».
const IconBanknote = (p) =>
<Ico {...p}>
    <rect x="3" y="7" width="18" height="10" rx="2" />
    <path d="M10 10v6M10 10h2.2a1.6 1.6 0 0 1 0 3.2H10" />
    <path d="M8.6 13.6H12" />
  </Ico>;

// Тренд вверх — растущая ломаная со стрелкой. Читается как «увеличение/множитель».
const IconTrendUp = (p) =>
<Ico {...p}>
    <path d="M3 17l6-6 4 4 8-8" />
    <path d="M15 7h6v6" />
  </Ico>;


/* expose for other babel scripts */
Object.assign(window, {
  cx, fmtRub, fmtRubStr, fmtRubDigits, fmtRubTight,
  SPButton, SPCard, SPPill, SPRow, SPAmountPreset, SPSnoozePrice, SnoozePriceCard,
  SPBalanceCard, SPSegmented, SPSwitch, SPStatusBar, SPNavBar, SPTabBar, SPInput,
  IconAlarm, IconWallet, IconStats, IconPlus, IconBack, IconClose, IconCheck,
  IconChevR, IconBell, IconFlame, IconCoin, IconArrowDn, IconArrowUp, IconShield,
  IconSound, IconChart, IconTrash, IconClock, IconUser, IconLock, IconLockScreen, IconBattery, IconSettings, IconSnooze, IconBanknote, IconTrendUp, IconRubleCoin, IconCoinOff
});