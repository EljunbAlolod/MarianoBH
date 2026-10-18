# Billing Dashboard Page Overrides

**Product:** MarianoBH  
**Platform:** Flutter / Android-first  
**Page type:** Financial operations dashboard

These rules override the master only for the Phase 6 billing dashboard and
statement flow. Generic web recommendations such as a 1400px canvas,
12-column grid, hover effects, and chart zoom do not apply.

## Layout

- Use a centered 900dp maximum content width, 16dp compact-phone gutters, and
  native vertical scrolling.
- Stack metric cards and status controls below 680dp or when text scaling makes
  a horizontal row unsafe. A 375dp phone at 200% text must have no horizontal
  clipping.
- Keep one primary action, **Create monthly bill**, followed by a visibly
  secondary unpaid-bills action. PDF remains explicitly labelled Phase 7.
- Show billed, collected, and outstanding as text-first cards. Do not introduce
  charts until multiple periods make a trend materially useful.

## Financial hierarchy and status

- Lead with the current half-open billing period and exact peso amounts.
- Always pair color with the labels **Unpaid**, **Partially paid**, **Paid**, or
  **Voided**. Status pills may wrap below dates and names.
- Treat finalized charges as an immutable snapshot. Put payment totals,
  remaining balances, and history in clearly separate sections.
- Show source readiness for electricity, water, and rent before enabling final
  review. Missing or mismatched dates must say what record is required.

## Forms and feedback

- Use native date pickers, numeric amount keyboards, persistent labels, and
  inline validation. Never allow a payment above the remaining bill balance.
- Disable duplicate-period and unavailable-source actions rather than allowing
  a predictably failing submission.
- Finalization and voiding require explicit confirmation. Explain that
  corrections preserve history and use a void/reissue flow.
- Async writes disable their initiating control, show progress, and finish with
  a success message or actionable error.

## Accessibility checks

- Touch targets remain at least 48×48dp.
- Long boarder names, peso values, and status labels wrap without truncating
  critical information.
- Screen-reader order follows period summary, totals, boarder bills, payments,
  then corrective actions.
- Verify light/dark themes, portrait/landscape, and large system text on a
  physical Android phone.
