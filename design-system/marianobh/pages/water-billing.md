# Water Billing Page Override

This page follows `../MASTER.md`. The rules below specialize it for Water
settings, calculation, and immutable history.

- Enter through the Billing utility hub so Electricity and Water remain two
  clear, related choices without adding a sixth bottom-navigation destination.
- Ask for the period and total bill before the method. Keep labels and helper
  text visible, state that the end date is exclusive, and use the peso keyboard.
- Recommend the saved method from the start month. Let the owner override it
  only when settings permit; the selected method must remain visible in the
  preview and saved record.
- Reveal electricity basis and source status only for Electricity percentage.
  Require an immutable electricity record with exactly matching dates. If none
  exists, disable Review and explain the two remedies: save that electricity
  period or choose Person-days.
- Show the full reconciliation before Save: original bill, allocated total,
  unallocated/landlady-paid total, method, warnings, and each boarder share.
  Never hide an empty-room allocation or silently divide by zero.
- Settings use native dropdowns, filter chips, and an adaptive switch. Keep at
  least one summer month selected and explain that electricity charge excludes
  documented adjustments.
- Saved water records are visibly read-only and retain room/boarder names,
  person-days, method, basis, source ID, warnings, and reconciled totals.
- Use `LayoutBuilder` for date fields and stacked summaries at compact widths or
  large text. Maintain 48dp controls, inline errors, keyboard-safe scrolling,
  dark-mode contrast, and explicit icon-plus-text statuses.
