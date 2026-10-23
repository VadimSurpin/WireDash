import 'package:flutter_test/flutter_test.dart';
import 'package:zigdash/features/settings/screens/settings_screen.dart';

void main() {
  test('Rate opens the real Play listing, also from a .dev test build', () {
    expect(
      playStoreAppUrl.toString(),
      'market://details?id=com.giladtamam.zigdash',
    );
    expect(
      playStoreWebUrl.toString(),
      'https://play.google.com/store/apps/details?id=com.giladtamam.zigdash',
    );
  });

  test('problem report opens the bug-report form with the version', () {
    final url = problemReportGithubUrl('2.0.1 (30)');
    expect(url.path, '/giladtamam/zigdash/issues/new');
    expect(url.queryParameters['template'], 'bug_report.yml');
    expect(url.queryParameters['version'], '2.0.1 (30)');
  });

  test('email goes to the developer with subject, prompt and version', () {
    final url = feedbackMailUrl(
      version: '2.0.1 (30)',
      subject: 'WireDash problem report',
      prompt: 'What happened, and what did you expect?',
    );
    expect(url.scheme, 'mailto');
    expect(url.path, reportEmail);
    expect(url.query, contains('subject=WireDash%20problem%20report'));
    expect(
      url.query,
      isNot(contains('+')),
      reason: 'mail apps show + literally',
    );
    final body = Uri.decodeComponent(url.query.split('&body=').last);
    expect(body, startsWith('What happened, and what did you expect?'));
    expect(body, endsWith('— WireDash 2.0.1 (30)'));
  });

  test('a problem report carries Support details instead of the version', () {
    const details = 'WireDash 2.0.1 (31)\nLast error: timed out';
    final gh = problemReportGithubUrl('2.0.1 (31)', details: details);
    expect(gh.queryParameters['details'], details);
    final mail = feedbackMailUrl(
      version: '2.0.1 (31)',
      subject: 'WireDash problem',
      prompt: 'What happened, and what did you expect?',
      details: details,
    );
    final body = Uri.decodeComponent(mail.query.split('&body=').last);
    expect(body, endsWith('— Support details —\n$details'));
    expect(body, isNot(contains('— WireDash 2.0.1')));
  });
}
