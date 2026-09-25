---
name: flutter-component-preview
description: Use to render, iterate on, or verify one Flutter widget in isolation, without starting the full app, auth, routing, or backend, across states and viewports.
---

When the Pickforge MCP server is connected, get its `preview-flutter-component` prompt with the target widget, states, and viewports, and follow it. It carries the same workflow with Pickforge sessions, screenshots, and evidence reports. Otherwise follow the steps below with the tools you have.

Record `git status --short` as the baseline. Then discover before generating anything. Find the Flutter command (`fvm flutter` when the repo has `.fvmrc`), the SDK version, the widget's constructor, and the theme, localization delegates, providers or inherited widgets, router and media dependencies, fonts, and assets it needs. Reuse existing test wrappers, builders, and fixtures rather than creating a second app or test convention. Take states and data from the request. Otherwise render the normal state plus long, empty, and error content where they apply. Capture 390, 768, and 1440 logical pixels at DPR 1 unless the project or request says otherwise. Supply valid Dart for the widget and its state yourself; do not guess constructors or provider state.

Choose lanes by purpose. Prefer the Flutter Widget Previewer for interactive visual iteration when the SDK supports `flutter widget-preview start`: write a temporary `@Preview` adapter whose `theme`, `localizations`, and `wrapper` supply the app's real theme, localizations, and inherited dependencies. Always use a widget-test capture harness for the checks: deterministic state matrices, exact logical sizes, overflow, semantics, and text scaling. Set the view size and DPR, pump each state, fail on overflow or any exception from `tester.takeException()`, and write any captures outside the source tree. Use a temporary web entrypoint only when the previewer is unavailable or cannot host the widget.

Serve visual lanes from your own shell, `flutter widget-preview start --web-server` or `flutter run -d web-server`, both on loopback, and view the URL in an isolated browser session with a private profile, never the user's browser or real desktop. Chrome cannot shrink to phone widths, so give each viewport its own preview or route that wraps the widget in a `MediaQuery` and `SizedBox` at the requested logical size.

In the widget-test harness, check each state for text scaling (at least 1.0 and 2.0), semantics labels, the tap target and text contrast guidelines with `meetsGuideline`, overflow and exceptions, and every responsive breakpoint the widget has. Use real project fonts and assets. Report rendering that is not deterministic or that differs between the widget-test and Chromium engines. Open and inspect every capture; a passing test does not replace looking at it.

Track every path you create and prefer paths outside the source tree. When Flutter needs a Dart file inside the package, use a unique name, confirm it did not exist, and record it. Never modify production routing, app startup, committed feature code, existing golden baselines, or files you did not create. Keep adapters, tests, screenshots, and logs temporary unless the user asks for permanent previews or golden baselines, and never accept or update goldens automatically.

Clean up in every outcome, including failure: stop the previewer or server and delete only the paths you recorded. If the run is interrupted, print the exact paths and commands still needed to clean up.

The preview is complete when every requested state and viewport has an inspected capture or a stated reason it could not be rendered, the accessibility and text-scale results are reported, and `git status --short` matches the baseline.
