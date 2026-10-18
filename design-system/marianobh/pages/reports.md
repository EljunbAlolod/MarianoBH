# Reports Page Overrides

**Product:** MarianoBH  
**Platform:** Flutter / Android-first  
**Page type:** Financial document preview and export

These rules override the master only for Phase 7 reports. The skill's generic
product-demo, web-hover, 1200px desktop, and 3D recommendations were rejected;
they do not fit a native operational document workflow.

## Layout

- Use one vertically scrollable report-configuration region above a persistent
  preview region. On short screens, configuration scrolls independently so the
  preview and Android system navigation remain reachable.
- Center content at a 1000dp maximum width with compact-phone gutters.
- Stack save and share actions below 560dp or at large text sizes. Selectors
  must expand inside their fields instead of clipping long labels.
- The preview uses the real generated A4 bytes. Monthly summaries may use A4
  landscape; individual statements use A4 portrait.

## Interaction and content

- Offer exactly three choices: monthly summary, all boarder statements, or one
  selected boarder statement. Regenerate the preview when selection changes.
- Keep **Share to Messenger / Other Apps** as the primary action and **Save
  PDF** as a subordinate action. Both stay disabled until generation succeeds.
- Explain that saving opens Android's native print/save dialog and sharing opens
  the native share sheet. Never promise automatic delivery to a group chat.
- Show a stable progress state during generation and an actionable retry state
  if generation or preview rasterization fails.

## Document rules

- Use a restrained trust-teal header, high-contrast text, repeating table
  headings, page numbers, and generated date. Avoid decorative imagery.
- Format money as `PHP 1,234.56` for offline compatibility with built-in PDF
  fonts. Use integer centavos as the source for every displayed amount.
- Pair payment color with explicit text: Unpaid, Partially paid, Paid, or
  Voided. Preserve correction reasons on voided historical versions.
- Exclude phone numbers, email credentials, and other unnecessary private data
  from group-ready summaries.

## Accessibility checks

- All Android touch targets remain at least 48dp and use native Material
  pressed/disabled states.
- Verify 375dp width at 200% text, portrait and landscape, light and dark mode.
- Give the preview a descriptive semantic label; selectors and actions retain
  visible labels and logical reading order.
- Do not rely on preview imagery alone: the report type, filename, save action,
  and share action remain accessible as native controls.
