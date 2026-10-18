# Partial-Month Billing Overrides

**Project:** MarianoBH  
**Platform:** Flutter / Android-first  
**Updated:** 2026-10-14

The UI/UX Pro Max search classified this as a low-friction financial form. Its
generic marketing palette, web font, and checkout-page suggestions were
rejected because they conflict with the operational mobile product. All rules
not listed here inherit from `design-system/marianobh/MASTER.md`.

## Layout

- Center content at a maximum width of 900dp; stack fields below 560dp or when
  system text scaling makes side-by-side content unsafe.
- Keep the whole workflow vertically scrollable and inside `SafeArea`.
- Use progressive disclosure: period and policy first, optional adjustments
  second, calculated review third, immutable save last.
- Value rows switch from horizontal to stacked at narrow widths or large text.

## Inputs and feedback

- Use native Material date pickers, labeled amount/reason fields, and semantic
  full-width policy choices with visible selected icons.
- Explain that the end date is exclusive beside the date inputs.
- Disable calculation when an occupied room has no monthly rent and name each
  room that needs correction.
- Keep charges and credits as separate dated entries with required reasons.
- Disable the save button while writing and show actionable errors in context.

## Financial clarity

- Label rent as exact because it comes from occupancy dates and room rates.
- Do not mix electricity estimates or water allocation into the rent result;
  each utility retains its own dedicated calculation and history.
- Show policy, period days, rent, signed adjustments, and grand total before
  confirmation. Show boarder and room reconciliation below the summary.
- Saved records display an explicit read-only status and snapshot explanation.

## Accessibility and validation

- Preserve Material 3 trust-teal semantic colors, native typography, 48dp
  touch targets, labeled icon controls, and non-color state indicators.
- Support 375x812 layouts at 200% text without horizontal overflow.
- Use integer centavos throughout; no visual rounding may disagree with the
  stored record.
