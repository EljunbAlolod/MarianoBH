# Billing Page Override

This page follows `../MASTER.md`. The rules below specialize it for meter entry
and electricity calculation.

- Lead with two plain-language actions: record meter readings and calculate an
  electricity period. Keep meter setup and reset/replacement actions on the
  relevant room card.
- Every numeric field keeps a visible label, unit, previous value, and inline
  validation. A submitting action shows progress and then a clear success or
  actionable error state.
- Use `LayoutBuilder` so summaries become a single column on compact phones or
  with large text. Never use a fixed-width meter-entry grid.
- Show the calculation trail: dated readings, kWh consumed, rate, base charge,
  documented adjustment, final room charge, and reconciled boarder shares.
- Pair warning colors with icons and text. Explicitly label occupancy-based
  distributions as estimates and show unallocated amounts as their own row.
- Meter reset/replacement is a confirmed workflow requiring an old closing
  reading, a new opening reading, an event date, and a reason. Never imply that
  prior readings will be overwritten.
- Saved electricity records are visibly read-only. Their room names, boarder
  names, readings, rate, allocation method, and totals are historical snapshots.
- Verify 375px portrait with 2x text, dark landscape, screen-reader order,
  48dp touch targets, keyboard-safe scrolling, and stable async states.
