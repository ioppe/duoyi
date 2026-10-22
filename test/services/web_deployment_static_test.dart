import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Web release and Pages each use their configured deployment path', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final deployScript = File('scripts/deploy_web_prod.sh').readAsStringSync();
    final webJobStart = workflow.indexOf('\n  web:\n');
    final deployPagesJobStart = workflow.indexOf(
      '\n  deploy-pages:\n',
      webJobStart,
    );
    final releaseJobStart = workflow.indexOf('\n  release:\n', webJobStart);
    expect(webJobStart, greaterThanOrEqualTo(0));
    expect(deployPagesJobStart, greaterThan(webJobStart));
    expect(releaseJobStart, greaterThan(webJobStart));

    final webJob = workflow.substring(webJobStart, deployPagesJobStart);
    expect(webJob, contains('DUOYI_BUILD_PROFILE'));
    expect(webJob, contains('scripts/flutter_with_config.py build web'));
    expect(webJob, contains('--base-href="\$PAGES_PATH"'));
    expect(webJob, contains('mv build/web build/web-pages'));
    expect(
      deployScript,
      contains('source "\$SCRIPT_DIR/deployment_common.sh"'),
    );
    expect(deployScript, contains('--base-href="\$BASE_HREF"'));
    expect(webJob, contains('--dart-define=DUOYI_WEB_TARGET=desktop'));
    expect(webJob, contains('--dart-define=DUOYI_WEB_TARGET=mobile'));
    expect(webJob, contains('mv build/web build/web-desktop'));
    expect(webJob, contains('mv build/web build/web-mobile'));
    expect(webJob, contains("github.ref == 'refs/heads/main'"));
    expect(webJob, contains('actions/upload-pages-artifact@v4'));
    expect(webJob, contains('path: build/web-pages'));
    expect(
      webJob,
      contains(
        'web-artifacts/duoyi-web-\$SUFFIX.tar.gz" -C build/web-desktop .',
      ),
    );
    expect(webJob, contains('web-artifacts/duoyi-web-desktop-\$SUFFIX.tar.gz'));
    expect(webJob, contains('web-artifacts/duoyi-web-mobile-\$SUFFIX.tar.gz'));
    expect(
      webJob,
      contains(
        'web-artifacts/duoyi-web-mobile-\$SUFFIX.tar.gz" -C build/web-mobile .',
      ),
    );

    final deployPagesJob = workflow.substring(
      deployPagesJobStart,
      releaseJobStart,
    );
    expect(deployPagesJob, contains("needs: web"));
    expect(deployPagesJob, contains("if: github.ref == 'refs/heads/main'"));
    expect(deployPagesJob, contains('pages: write'));
    expect(deployPagesJob, contains('id-token: write'));
    expect(deployPagesJob, contains('name: github-pages'));
    expect(deployPagesJob, contains('actions/deploy-pages@v4'));

    expect(
      workflow,
      contains('DUOYI_PAGES_BASE_HREF'),
      reason: 'GitHub Pages must not reuse a root-based self-hosted artifact.',
    );
    expect(deployScript, contains('version_family="\${VERSION_NAME%.*}"'));
    expect(deployScript, contains('\${version_family//./\\\\.}\\\\.[0-9]+'));
    expect(deployScript, isNot(contains("'[0-9]+\\\\.[0-9]+\\\\.[0-9]+'")));

    final downloadPage = File('deploy/duoyi.html').readAsStringSync();
    expect(downloadPage, contains('href="/duoyi/"'));
    expect(downloadPage, contains('http://6688667.xyz/duoyi/'));
    expect(downloadPage, contains('duoyi-web-desktop-v1.1.43.tar.gz'));
    expect(downloadPage, contains('duoyi-web-mobile-v1.1.43.tar.gz'));
    expect(downloadPage, isNot(contains('v1.1.39')));
    expect(downloadPage, isNot(contains('v1.1.38')));
    expect(downloadPage, isNot(contains('v1.1.37')));
    expect(downloadPage, isNot(contains('duoyi-v1.1.35.apk')));

    final webTarget = File('lib/core/web_target.dart').readAsStringSync();
    final appConfig = File('lib/core/app_config.dart').readAsStringSync();
    expect(webTarget, contains('AppConfig.webTarget'));
    expect(appConfig, contains("String.fromEnvironment("));
    expect(appConfig, contains("'DUOYI_WEB_TARGET'"));
    expect(webTarget, contains("raw == 'desktop'"));
    expect(webTarget, contains("raw == 'mobile'"));

    final preferencesProvider = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    expect(preferencesProvider, contains('webDefaultBottomNavTabs'));
    expect(
      preferencesProvider,
      contains('webDefaultBottomNavTabs = <int>{0, 1, 2, 4, 6}'),
    );
    expect(preferencesProvider, contains('isBottomNavTabSupported'));
    expect(preferencesProvider, contains('normalizeDefaultTab'));
    expect(preferencesProvider, contains('tab == 5'));

    final main = File('lib/main.dart').readAsStringSync();
    expect(preferencesProvider, contains('WebTarget.isWebBuild'));
    expect(main, contains('PreferencesProvider.isBottomNavTabSupported(tab)'));
    expect(main, isNot(contains('_desktopWebVisibleBottomNavTabs')));

    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(
      moreApps,
      contains('PreferencesProvider.isBottomNavTabSupported(app.tab)'),
    );

    final preferencesScreen = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    expect(preferencesScreen, isNot(contains('WebTarget.isDesktopWebBuild')));
    expect(preferencesScreen, contains('isBottomNavTabSupported(tab)'));
    expect(
      preferencesScreen,
      contains('where(PreferencesProvider.isBottomNavTabSupported)'),
    );

    final widgetScreen = File(
      'lib/screens/widget_screen.dart',
    ).readAsStringSync();
    expect(widgetScreen, contains('desktop_web_widget_fallback'));
    expect(widgetScreen, contains('WidgetPreviewCard.calendar'));
    expect(widgetScreen, contains('const CalendarScreen()'));

    final sourceIndex = File('web/index.html').readAsStringSync();
    expect(sourceIndex, contains('<base href="\$FLUTTER_BASE_HREF">'));
    expect(sourceIndex, contains('the `--base-href` argument'));
    expect(sourceIndex, isNot(contains('<base href="/">')));
  });
}
