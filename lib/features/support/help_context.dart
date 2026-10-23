/// The place that opened contextual help. Used locally to choose tips and
/// explain user-initiated support requests; never collected or transmitted.
enum HelpFrom {
  noConnection,
  setupError,
  manualConnect,
  manualForm,
  homeUnreachable,
  deviceListMissing,
  settings,
  demo,
  card,
}
