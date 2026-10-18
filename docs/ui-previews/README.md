# UI modernization checkpoint

Preview images are generated from widget tests with fake empty owner data at
412 × 915 logical pixels. They are not physical-phone screenshots. A locally
installed font is supplied with `UI_PREVIEW_FONT` for readable rendering.

This checkpoint implements:
- Shared neutral/teal Material theme, typography and icon/touch-target standards.
- Stateful bottom navigation branches and retained search state.
- Current combined-utility and recorded-rent balances on Home.
- Compact property overview, quick actions and operational task links.
- Grouped Billing hub, Rooms/Boarders search, and clearer water inclusion cards.

## Skill-guided UI sweep

The follow-up adds shared dialog/sheet/chip/expansion/button styling throughout
the app, responsive authentication, wide-screen navigation rail, teal workspace
headers, dedicated room details, boarder section hierarchy, utility workflow
progress labels, neutral financial metrics, and Settings/PDF presentation polish.
Legacy screens inherit shared theme and state-panel improvements rather than
new workflows. Physical Android QA remains pending.

Previews: [Home](home.png), [Billing](billing.png), [Login](login.png),
[Rooms](rooms.png), [Boarders](boarders.png), [Create bill](create-bill.png).
These are empty-state widget renders, not photographs of a running phone.

Regenerate using:

```powershell
flutter test --no-pub test/app/modern_ui_test.dart --plain-name "capture modern Home and Billing previews" --update-goldens --dart-define="UI_PREVIEW_FONT=C:\Windows\Fonts\segoeui.ttf"
```

No billing formulas, persistence models, authentication policy, or Firestore
rules are changed by this UI checkpoint.

## Verification results

- Flutter analysis: no issues.
- Full Flutter suite after the main sweep: 163 passed and one opt-in preview
  test skipped. Subsequent room-navigation, rail-navigation and PDF presentation
  checks: 31 passed, one skipped. Preview generation passed separately.
- Responsive navigation tests: 360, 375, 412, and 800dp widths; 1× and 2× text;
  light and dark mode. Verified search state survives switching tabs.
- Home summary test verifies current combined utility account amounts rather
  than legacy billing-cycle amounts.
- Home, Login and Create bill previews were rendered and visually inspected. They use
  empty test data and a local Segoe UI font substitute, with Material icons.
- No before screenshots were captured. No physical Android device was detected;
  physical-phone verification remains pending.
