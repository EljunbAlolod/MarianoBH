# MarianoBH Mobile Design System

**Product:** Owner-operated boarding-house management app  
**Platform:** Flutter / Android-first, responsive to larger screens  
**Direction:** Minimal, trustworthy, operational, and calm  
**Design dials:** Variance 3/10, motion 2/10, density 7/10

> The UI/UX Pro Max product matcher returned landing-page and luxury-property
> patterns that did not fit a daily operations app. Those parts were rejected.
> This master keeps the verified Minimalism/Swiss direction, Flutter guidance,
> mobile UX rules, and accessibility defaults from the skill.

## Foundations

### Skill-guided UI sweep

Installed UI/UX Pro Max in `.agents/skills/ui-ux-pro-max`. Queried
`billing operations dashboard --design-system` and
`responsive forms navigation --stack flutter` using `py -3`.
Accepted the Minimalism/Swiss styling, content-sized LayoutBuilder layouts,
semantic contrast and declarative navigation recommendations. The marketing
conversion pattern, web font imports and GSAP animation output are unsuitable
for this native operational app; the existing teal identity is retained.

- `PageIntro` gives main workspaces a consistent, content-sized teal header.
- `WorkflowProgress` wraps its step labels and announces the current step.
- Financial metric cards use neutral surfaces and tabular figures.
- Shared dialog, sheet, chip, expansion and button themes also style legacy
  screens, report controls and payment forms.
- At 1000dp and above, standard-size text uses a labeled navigation rail;
  phones and large text retain the bottom navigation.
- Authentication uses one column on phones and a two-column layout from
  960dp with standard-size text. Both layouts scroll with the keyboard.
- Room names open `/rooms/:roomId`; details expose rent, current occupants,
  editing, and meter-history navigation. Back restores the rooms list.

### Implemented modernization tokens

- Action and navigation icons: 24dp; supporting indicators: 18–20dp;
  feature shortcuts: 22–24dp; empty-state icons: 48dp.
- Icon buttons retain 48dp minimum touch targets independent of artwork size.
- Light background: `#F6F7F9`, with semantic surface colors for cards and dark mode.
- Screen/app-bar titles: 22–26sp; section titles: 19sp; body: 14–16sp.
- Financial amounts use tabular figures and a 24sp heading style.
- `AdaptiveTiles` uses content-height layouts and collapses to one column for
  large text. No fixed-aspect-ratio cards for financial amounts or labels.
- `SectionHeader`, `FinancialAmount`, `ActionListItem`, and `RecordSearchField`
  are shared under `lib/shared/widgets/app_components.dart`.

- Use Material 3 and platform-native sans-serif typography. Do not load a web
  font; clarity, offline resilience, and Dynamic Type behavior take priority.
- Use semantic `ColorScheme` tokens everywhere. The trust-teal family is the
  brand direction: seed `#0F766E`, with professional blue only when a distinct
  informational accent is needed.
- Support both light and dark color schemes. Body text must maintain at least
  4.5:1 contrast; meaningful controls and icons need at least 3:1.
- Use a 4/8dp rhythm: 4, 8, 12, 16, 24, 32, and 48. Standard screen gutters are
  16dp on compact phones, 24dp on medium widths, and a centered max width on
  tablets.
- Cards use restrained borders or low elevation, 16dp corners, and no
  decorative gradients. Information hierarchy comes from spacing and type.

## Interaction

- Every Android touch target is at least 48x48dp with at least 8dp separation.
- Prefer native Material buttons, list tiles, dialogs, sheets, date pickers,
  text fields, and navigation so ripple, focus, and semantics are preserved.
- Async actions disable the initiating control and show progress, followed by
  clear success or actionable error feedback. Keep field errors beside fields.
- Use subtle, meaningful motion only. Never hide required content behind an
  entrance animation; honor reduced-motion settings by avoiding custom motion.
- Confirm destructive-looking status changes, but never imply that historical
  financial or occupancy data will be deleted.

## Navigation and Content

- Bottom navigation has five stable destinations: Home, Rooms, Boarders,
  Billing, and Settings. Detail screens deep-link and retain a predictable
  system back path.
- Independent `StatefulShellRoute` branches retain visited tab state. Boarder
  list-to-detail navigation pushes a page so Back returns to the list.
- Use visible text labels with Material icons; no emoji or image-based icons.
- Room cards show status, rent, occupancy count, and current boarder names.
  Boarder cards show lifecycle status, current room, and the next valid action.
- Empty, loading, offline, and retry states are first-class layouts. Long names,
  larger text, narrow 375px phones, and landscape must reflow without clipping.
- Forms use persistent labels, appropriate keyboards, inline validation, and a
  single clear primary action. Dates explain that move-out is the first
  non-billable day.

## Pre-delivery Checks

- No horizontal overflow at 375px or in landscape.
- No scroll content hidden behind the bottom navigation or keyboard.
- Screen-reader order follows visual order and icon-only controls have labels.
- Color is never the only status indicator; pair it with text and/or an icon.
- Verify light/dark themes, largest text scaling, safe areas, disabled states,
  physical-phone interaction, and all touch targets before release.
