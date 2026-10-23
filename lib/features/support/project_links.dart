import 'package:url_launcher/url_launcher.dart';

const projectUrl = 'https://github.com/VadimSurpin/WireDash';
final releasesUrl = Uri.parse('$projectUrl/releases/latest');
final setupGuideUrl = Uri.parse('$projectUrl/blob/HEAD/docs/USER_GUIDE.md');

/// An editable draft. Opening it never submits an issue on the user's behalf.
Uri problemReportGithubUrl(String version, {String? details}) =>
    Uri.parse('$projectUrl/issues/new').replace(
      queryParameters: {
        'template': 'bug_report.yml',
        'version': version,
        if (details != null) 'details': details,
      },
    );

/// Invoked by explicit help/report actions only; replaceable in tests.
Future<bool> Function(Uri url) openSupportLink = (url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
