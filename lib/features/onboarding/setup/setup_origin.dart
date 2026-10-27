/// Local setup navigation context. No usage events are recorded or transmitted.
enum SetupVia { scan, homeAssistant, brokerForm, shared, z2mPage }

enum HaSignInFrom {
  scanning,
  emptyCard,
  emptyChoice,
  haFound,
  login,
  manualForm,
  noWifi,
  welcome,
}
