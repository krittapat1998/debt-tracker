# Screenshots

Regenerates the images in `docs/screenshots/` from the iOS Simulator (macOS only).

1. Run the app on a booted simulator once, then quit it.
2. Fill it with made-up data (theme: `light`, `dark`, `blue` or `system`):

   ```bash
   U=<simulator udid>
   DB="$(xcrun simctl get_app_container $U com.krittapat.debtTracker data)/Documents/debt_tracker.db"
   python3 tool/screenshots/seed_demo.py "$DB" light
   xcrun simctl status_bar $U override --time 9:41 --batteryState charged --batteryLevel 100
   xcrun simctl launch $U com.krittapat.debtTracker
   ```

3. Take raw screenshots with `xcrun simctl io $U screenshot <name>.png`.
4. Frame and compose them (uses the Sukhumvit Set font that ships with macOS):

   ```bash
   swift tool/screenshots/showcase.swift frame docs/screenshots/dashboard.png dashboard.png 520
   swift tool/screenshots/showcase.swift hero docs/screenshots/hero.png assets/icon/app_icon.png chart.png dashboard.png cards.png
   swift tool/screenshots/showcase.swift gallery docs/screenshots/gallery.png dashboard.png "ภาพรวม" plan.png "แผนปลดหนี้"
   ```
