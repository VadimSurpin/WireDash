// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get reliabilityLastKnown => 'Último valor conhecido';

  @override
  String get reliabilityControlsUnavailable => 'Controles indisponíveis';

  @override
  String get appTitle => 'ZigDash';

  @override
  String get onboardingDemo => 'Testar demo';

  @override
  String get navBrokers => 'Brokers';

  @override
  String get navDashboards => 'Painéis';

  @override
  String get navSettings => 'Configurações';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get settingsDynamicColor => 'Usar cores do Material You';

  @override
  String get settingsDynamicColorSubtitle =>
      'Android 12+; caso contrário, usa a cor do app';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get languageEnglish => 'Inglês';

  @override
  String get languageHebrew => 'עברית';

  @override
  String get connectionsTitle => 'Casas';

  @override
  String connLoadFailed(Object error) {
    return 'Falha ao carregar: $error';
  }

  @override
  String get connAddBroker => 'Adicionar broker';

  @override
  String get connEmpty =>
      'Nenhuma conexão ainda.\nToque em \"Adicionar broker\" para apontar o ZigDash para seu servidor MQTT.';

  @override
  String get connNew => 'Nova conexão';

  @override
  String get connEdit => 'Editar conexão';

  @override
  String get save => 'Salvar';

  @override
  String get saving => 'Salvando…';

  @override
  String get fieldRequired => 'Obrigatório';

  @override
  String get connName => 'Nome';

  @override
  String get connNameHint => 'Broker de casa';

  @override
  String get connHost => 'Host';

  @override
  String get connHostHint => '192.168.1.10';

  @override
  String get connLocalHost => 'Host local';

  @override
  String get connFindBrokers => 'Procurar brokers';

  @override
  String get connHowToFind => 'Como encontro isso?';

  @override
  String get connRescan => 'Procurar de novo';

  @override
  String get connBrokerNeedsLogin => 'Requer login';

  @override
  String connFindBrokersScanning(Object subnet) {
    return 'Verificando $subnet…';
  }

  @override
  String connFindBrokersFound(int count) {
    return '$count broker(s) encontrado(s) — toque para usar';
  }

  @override
  String get connFindBrokersNone => 'Nenhum broker encontrado no seu Wi-Fi.';

  @override
  String get connFindBrokersNoIp =>
      'Não foi possível ler o endereço do seu Wi-Fi. Verifique se o Wi-Fi está ligado e tente de novo.';

  @override
  String get connHelpTitle => 'Como encontrar o IP do broker';

  @override
  String get connHelpDockerTitle => 'Zigbee2MQTT no Docker';

  @override
  String get connHelpDockerBody =>
      'O IP do broker é o endereço na rede local da máquina que roda o Docker (seu NAS, Raspberry Pi etc.). Encontre-o na lista de dispositivos do roteador ou execute \'hostname -I\' / \'ip addr\' nessa máquina. A porta costuma ser 1883 (Mosquitto). Use o IP local do host — não 127.0.0.1 — mesmo que o Mosquitto rode em um contêiner próprio.';

  @override
  String get connHelpSmhubTitle => 'SMLIGHT SMHUB';

  @override
  String get connHelpSmhubBody =>
      'O IP do broker é o endereço IP do hub. Encontre-o na interface web da SMLIGHT em Settings → Network ou no seu roteador. A porta é 1883, sem usuário/senha por padrão.';

  @override
  String get connHelpZhaTitle => 'Home Assistant ZHA';

  @override
  String get connHelpZhaBody =>
      'O ZHA não tem broker MQTT — ele fala direto com o Home Assistant, então o ZigDash não consegue se conectar a ele. Para usar o ZigDash, migre para o Zigbee2MQTT (disponível como add-on do Home Assistant ou contêiner Docker), que fornece um broker MQTT.';

  @override
  String get connHelpSameNetwork =>
      'Seu celular e o broker precisam estar na mesma rede Wi-Fi (não em uma rede de convidados ou VLAN isolada).';

  @override
  String get connRemoteHost => 'Host remoto (Tailscale)';

  @override
  String get connRemoteHostHint =>
      'Usado quando o host local não está acessível. Prefira o IP Tailscale do hub, por ex. 100.x.y.z';

  @override
  String get connPort => 'Porta';

  @override
  String get connPortRange => '1–65535';

  @override
  String get connUsername => 'Usuário';

  @override
  String get connUsernameOptional => 'Usuário (opcional)';

  @override
  String get connPasswordOptional => 'Senha (opcional)';

  @override
  String get connPasswordKeepHint => 'Deixe em branco para manter a atual';

  @override
  String get connAutoConnect => 'Conectar automaticamente ao abrir o app';

  @override
  String get advanced => 'Avançado';

  @override
  String get connKeepAlive => 'Keep-alive (segundos)';

  @override
  String get connKeepAliveRange => '5–3600';

  @override
  String get connProtocol => 'Protocolo';

  @override
  String get edit => 'Editar';

  @override
  String get delete => 'Excluir';

  @override
  String get cancel => 'Cancelar';

  @override
  String get connDeleteTitle => 'Excluir conexão?';

  @override
  String connDeleteContent(Object name) {
    return 'Remove \"$name\", seus painéis/blocos e a senha salva.';
  }

  @override
  String get statusDisconnected => 'Desconectado';

  @override
  String get statusConnecting => 'Conectando';

  @override
  String get statusConnected => 'Conectado';

  @override
  String get statusReconnecting => 'Reconectando';

  @override
  String get statusError => 'Erro';

  @override
  String get statusConnectedRemote => 'Conectado · Remoto';

  @override
  String get dashPlaceholder =>
      'Abra um broker na aba Brokers para ver e gerenciar os painéis dele.';

  @override
  String get dashAddDashboard => 'Adicionar painel';

  @override
  String get dashEditDashboard => 'Editar painel';

  @override
  String get dashAddPanel => 'Adicionar bloco';

  @override
  String get dashEmpty =>
      'Nenhum painel ainda.\nToque em \"Adicionar painel\" para criar um para este broker.';

  @override
  String dashLoadFailed(Object error) {
    return 'Falha: $error';
  }

  @override
  String get panelPickerTitle => 'Adicionar um bloco';

  @override
  String get panelPickerSectionControl => 'Controle';

  @override
  String get panelPickerSectionState => 'Estado';

  @override
  String get panelPickerToggleTitle => 'Interruptor';

  @override
  String get panelPickerToggleSubtitle =>
      'Liga/desliga para o estado de um dispositivo';

  @override
  String get panelPickerSliderBrightnessTitle => 'Controle deslizante — Brilho';

  @override
  String get panelPickerSliderBrightnessSubtitle =>
      'Dimerização de luz (0–254, brightness:N)';

  @override
  String get panelPickerSliderPositionTitle => 'Controle deslizante — Posição';

  @override
  String get panelPickerSliderPositionSubtitle =>
      'Persiana / cortina (0–100, position:N)';

  @override
  String get panelPickerCoverTitle => 'Persiana';

  @override
  String get panelPickerCoverSubtitle =>
      'Persiana/cortina: OPEN·STOP·CLOSE + controle de posição';

  @override
  String get panelPickerScheduleTitle => 'Agendamento';

  @override
  String get panelPickerScheduleSubtitle =>
      'Horários diários de abrir/fechar, executados no hub (Node-RED)';

  @override
  String get panelPickerAutoCloseTitle => 'Regra de fechamento automático';

  @override
  String get panelPickerAutoCloseSubtitle =>
      'Fecha um dispositivo automaticamente N segundos depois de ligar, executado no hub (Node-RED)';

  @override
  String get panelPickerMultiStateTitle => 'Multiestado';

  @override
  String get panelPickerMultiStateSubtitle =>
      'Botões segmentados para um enum (ex.: OPEN/STOP/CLOSE)';

  @override
  String get panelPickerComboTitle => 'Lista suspensa';

  @override
  String get panelPickerComboSubtitle => 'Seletor suspenso para um enum';

  @override
  String get panelPickerRadioTitle => 'Opções';

  @override
  String get panelPickerRadioSubtitle =>
      'Lista de botões de opção para um enum';

  @override
  String get panelPickerButtonTitle => 'Botão';

  @override
  String get panelPickerButtonSubtitle => 'Envia um comando único';

  @override
  String get panelPickerTextInputTitle => 'Entrada de texto';

  @override
  String get panelPickerTextInputSubtitle => 'Publica um valor livre ou JSON';

  @override
  String get panelPickerLedTitle => 'LED';

  @override
  String get panelPickerLedSubtitle =>
      'Indicador colorido para um estado booleano (contato, vazamento)';

  @override
  String get panelPickerNodeStatusTitle => 'Status do nó';

  @override
  String get panelPickerNodeStatusSubtitle =>
      'Disponibilidade do dispositivo no Z2M (online/offline)';

  @override
  String get panelPickerProgressTitle => 'Progresso';

  @override
  String get panelPickerProgressSubtitle =>
      'Barra numérica para bateria, qualidade do link etc.';

  @override
  String get panelPickerTextLogTitle => 'Log de texto';

  @override
  String get panelPickerTextLogSubtitle =>
      'Histórico rolável das mensagens de um tópico';

  @override
  String get dashExportMenu => 'Exportar painéis';

  @override
  String get dashImportMenu => 'Importar painéis';

  @override
  String get dashExportTitle => 'Exportar painéis';

  @override
  String get dashExportClose => 'Fechar';

  @override
  String get dashExportCopy => 'Copiar';

  @override
  String get dashExportCopied => 'Copiado para a área de transferência';

  @override
  String get dashImportTitle => 'Importar painéis';

  @override
  String get dashImportHint => 'Cole aqui o JSON exportado';

  @override
  String get dashImportButton => 'Importar';

  @override
  String dashImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count painéis importados',
      one: '1 painel importado',
    );
    return '$_temp0';
  }

  @override
  String dashImportFailed(Object error) {
    return 'Falha na importação: $error';
  }

  @override
  String get dashFormNew => 'Novo painel';

  @override
  String get dashFormEdit => 'Editar painel';

  @override
  String get dashFormName => 'Nome';

  @override
  String get dashFormNameHint => 'Escritório';

  @override
  String get dashFormTopicPrefix => 'Prefixo de tópico (opcional)';

  @override
  String get dashFormTopicPrefixHint => 'zigbee2mqtt/living-room';

  @override
  String get dashFormTopicPrefixHelper =>
      'Adicionado antes de todo tópico de bloco deste painel';

  @override
  String get dashFormColorSeed => 'Cor base';

  @override
  String get dashFormIcon => 'Ícone';

  @override
  String get dashFormLock => 'Bloqueio de edição';

  @override
  String get dashFormLockSubtitle => 'Oculta Editar neste painel';

  @override
  String get dashFormDelete => 'Excluir painel';

  @override
  String get dashDeleteTitle => 'Excluir este painel?';

  @override
  String get dashDeleteContent =>
      'Todos os blocos dele também serão removidos.';

  @override
  String get dashDeleteConfirm => 'Excluir';

  @override
  String panelFormNew(Object type) {
    return 'Novo: $type';
  }

  @override
  String panelFormEdit(Object type) {
    return 'Editar $type';
  }

  @override
  String get panelTypeButton => 'Botão';

  @override
  String get panelTypeToggle => 'Interruptor';

  @override
  String get panelTypeSlider => 'Controle deslizante';

  @override
  String get panelTypeLed => 'LED';

  @override
  String get panelTypeNodeStatus => 'Status do nó';

  @override
  String get panelTypeProgress => 'Progresso';

  @override
  String get panelTypeMultiState => 'Multiestado';

  @override
  String get panelTypeCombo => 'Lista suspensa';

  @override
  String get panelTypeRadio => 'Opções';

  @override
  String get panelTypeCover => 'Persiana';

  @override
  String get panelTypeTextInput => 'Entrada de texto';

  @override
  String get panelTypeTextLog => 'Log de texto';

  @override
  String get panelTypeSchedule => 'Agendamento';

  @override
  String get panelTypeAutoClose => 'Fechamento automático';

  @override
  String get panelTypeDevice => 'Dispositivo';

  @override
  String get panelTypeReading => 'Leitura';

  @override
  String get panelFormName => 'Nome';

  @override
  String panelFormDashboardPrefix(Object prefix) {
    return 'Prefixo do painel: $prefix/ (usado, a menos que substituído abaixo)';
  }

  @override
  String get panelFormTopicPrefixOverride =>
      'Substituir prefixo de tópico (opcional)';

  @override
  String get panelFormTopicPrefixOverrideHint => 'zigbee2mqtt/shutter';

  @override
  String get panelFormTopicPrefixOverrideHelper =>
      'Use outro dispositivo neste painel. Em branco = usar o prefixo do painel.';

  @override
  String get panelFormPublishTopic => 'Tópico de publicação (sufixo)';

  @override
  String get panelFormPublishTopicHint => 'set';

  @override
  String get panelFormPublishTopicHelper =>
      'Adicionado ao final do prefixo efetivo. Deixe em branco para publicar no próprio prefixo.';

  @override
  String get panelFormTopicSuffix => 'Tópico (sufixo)';

  @override
  String get panelFormSubscribeTopic =>
      'Tópico de inscrição (sufixo, opcional)';

  @override
  String get panelFormSubscribeTopicHelperReadOnly =>
      'Adicionado ao final do prefixo do painel. Em branco = inscrever-se no próprio prefixo (estado do Z2M).';

  @override
  String get panelFormSubscribeTopicHelper =>
      'Em branco = inscrever-se no próprio prefixo (estado do Z2M). Igual ao tópico de publicação = usar esse.';

  @override
  String get tileSize => 'Tamanho';

  @override
  String get tileSizeSmall => 'Pequeno';

  @override
  String get tileSizeWide => 'Largo';

  @override
  String get tileSizeFull => 'Inteiro';

  @override
  String get panelFormQos => 'QoS';

  @override
  String get panelFormQos0 => '0 — no máximo uma vez';

  @override
  String get panelFormQos1 => '1 — pelo menos uma vez';

  @override
  String get panelFormQos2 => '2 — exatamente uma vez';

  @override
  String get panelFormRetain => 'Reter (retain)';

  @override
  String get panelToggleOnPayload => 'Payload de ligar';

  @override
  String get panelToggleOffPayload => 'Payload de desligar';

  @override
  String get panelToggleJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelToggleJsonPathHint => 'state';

  @override
  String get panelToggleOnMatch => 'Valor de ligado';

  @override
  String get panelToggleOnMatchHelper =>
      'Valor no caminho JSON que significa \"ligado\" (ex.: \"ON\")';

  @override
  String get panelSliderMin => 'Mín.';

  @override
  String get panelSliderMax => 'Máx.';

  @override
  String get panelSliderStep => 'Passo';

  @override
  String get panelSliderTemplate => 'Modelo de valor';

  @override
  String get panelSliderTemplateHelper =>
      'Use a palavra value como marcador — ela é substituída pelo valor do controle';

  @override
  String get panelSliderJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelSliderJsonPathHint => 'brightness';

  @override
  String get panelButtonPayload => 'Payload';

  @override
  String get panelLedJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelLedJsonPathHint => 'contact';

  @override
  String get panelLedJsonPathHelper =>
      'ex.: \"contact\", \"occupancy\", \"water_leak\"';

  @override
  String get panelLedOnMatch => 'Valor de aceso';

  @override
  String get panelLedOnMatchHelper =>
      'Valor no caminho JSON que acende o LED (ex.: \"true\", \"ON\")';

  @override
  String get panelLedOnLabel => 'Rótulo ligado (opcional)';

  @override
  String get panelLedOnLabelHint => 'ON';

  @override
  String get panelLedOffLabel => 'Rótulo desligado (opcional)';

  @override
  String get panelLedOffLabelHint => 'OFF';

  @override
  String get panelNodeOnlinePayload => 'Payload de online';

  @override
  String get panelNodeOnlinePayloadHelper =>
      'Valor que significa \"online\" (padrão do Z2M: \"online\")';

  @override
  String get panelNodeJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelNodeJsonPathHelper =>
      'Deixe em branco para o padrão do Z2M (texto bruto \"online\"/\"offline\")';

  @override
  String get panelProgressMin => 'Mín.';

  @override
  String get panelProgressMax => 'Máx.';

  @override
  String get panelProgressUnit => 'Unidade';

  @override
  String get panelProgressUnitHint => '%';

  @override
  String get panelProgressJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelProgressJsonPathHint => 'battery';

  @override
  String get panelProgressJsonPathHelper => 'ex.: \"battery\", \"linkquality\"';

  @override
  String get panelOptionsJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelOptionsJsonPathHint => 'state';

  @override
  String get panelOptionsJsonPathHelper =>
      'Campo do payload recebido que contém o valor atual';

  @override
  String get panelOptionsHeader => 'Opções';

  @override
  String get panelOptionsLabel => 'Rótulo';

  @override
  String get panelOptionsPayload => 'Payload';

  @override
  String get panelOptionsMatch => 'Correspondência (valor atual)';

  @override
  String get panelOptionsAdd => 'Adicionar opção';

  @override
  String get panelCoverDescription =>
      'Botões OPEN / STOP / CLOSE e uma linha de posições predefinidas. Usa os payloads padrão de persiana do Z2M (state e position).';

  @override
  String get panelCoverPresets => 'Posições predefinidas';

  @override
  String get panelCoverPresetsHint => '0, 25, 50, 100';

  @override
  String get panelCoverPresetsHelper =>
      'Porcentagens separadas por vírgula (0–100). Em branco = sem linha de predefinições.';

  @override
  String get panelCoverShowSlider => 'Mostrar controle de posição';

  @override
  String get panelTextInputHint => 'Dica (opcional)';

  @override
  String get panelTextInputHintHint => 'Digite um valor…';

  @override
  String get panelTextInputTemplate => 'Modelo';

  @override
  String get panelTextInputTemplateHelper =>
      'Use a palavra value como marcador — ela é substituída pelo texto digitado. Por padrão, publica o texto bruto.';

  @override
  String get panelTextInputClearAfterSend => 'Limpar após enviar';

  @override
  String get panelTextLogMaxLines => 'Máx. de linhas';

  @override
  String get panelTextLogMaxLinesHelper => 'Quantas mensagens recentes manter';

  @override
  String get panelTextLogJsonPath => 'Caminho JSON (opcional)';

  @override
  String get panelTextLogJsonPathHelper =>
      'Registra só este campo em vez do payload inteiro';

  @override
  String get panelScheduleDescription =>
      'Roda no SMHUB via Node-RED — funciona mesmo com este celular desligado. O tópico de publicação acima é o destino dos comandos da persiana.';

  @override
  String get panelScheduleOpenTime => 'Horário de abrir';

  @override
  String get panelScheduleCloseTime => 'Horário de fechar';

  @override
  String get panelScheduleOpenPayload => 'Payload de abrir';

  @override
  String get panelScheduleClosePayload => 'Payload de fechar';

  @override
  String get panelScheduleEnabled => 'Ativado';

  @override
  String get panelScheduleSavedOffline =>
      'Salvo — sem conexão; o agendamento será sincronizado quando estiver online.';

  @override
  String get panelAutoCloseDescription =>
      'Roda no SMHUB via Node-RED — funciona mesmo com este celular desligado. O tópico de publicação acima é o destino dos comandos do dispositivo (ex.: porta).';

  @override
  String get panelAutoCloseTriggerPath => 'Caminho JSON do gatilho';

  @override
  String get panelAutoCloseTriggerPathHelper =>
      'Campo do JSON de estado do dispositivo a observar (padrão: state)';

  @override
  String get panelAutoCloseTriggerValue => 'Valor do gatilho';

  @override
  String get panelAutoCloseTriggerValueHelper =>
      'Inicia o timer quando o campo do gatilho for igual a este valor (padrão: ON)';

  @override
  String get panelAutoCloseClosePayload => 'Payload de fechar';

  @override
  String get panelAutoCloseDelaySeconds => 'Atraso (segundos)';

  @override
  String get panelAutoCloseDelaySecondsHelper =>
      '1-3600. Tempo de espera depois que o dispositivo liga, antes de publicar o payload de fechar.';

  @override
  String get panelAutoCloseEnabled => 'Ativado';

  @override
  String get panelAutoCloseSavedOffline =>
      'Salvo — sem conexão; a regra será sincronizada quando estiver online.';

  @override
  String get panelTileEdit => 'Editar bloco';

  @override
  String get panelTileDuplicate => 'Duplicar bloco';

  @override
  String get panelTileMoveUp => 'Mover para cima';

  @override
  String get panelTileMoveDown => 'Mover para baixo';

  @override
  String get panelTileDelete => 'Excluir bloco';

  @override
  String get panelCoverOpen => 'Abrir';

  @override
  String get panelCoverStop => 'Parar';

  @override
  String get panelCoverClose => 'Fechar';

  @override
  String get panelToggleNoState => '(sem estado)';

  @override
  String get panelToggleError => 'erro';

  @override
  String get panelStateOn => 'LIGADO';

  @override
  String get panelStateOff => 'DESLIGADO';

  @override
  String get panelNodeStatusOnline => 'online';

  @override
  String get panelNodeStatusOffline => 'offline';

  @override
  String get panelNodeStatusUnknown => 'desconhecido';

  @override
  String get panelNodeStatusError => 'erro';

  @override
  String get panelMultiStateNoOptions => 'Nenhuma opção configurada';

  @override
  String get panelTextInputDefaultHint => 'Digite um valor…';

  @override
  String get panelTextLogWaiting => 'Aguardando mensagens…';

  @override
  String panelScheduleOpensAt(Object time) {
    return 'Abre às $time';
  }

  @override
  String panelScheduleClosesAt(Object time) {
    return 'Fecha às $time';
  }

  @override
  String get panelScheduleOfflineWarning => 'Agendador offline — não vai rodar';

  @override
  String get panelScheduleDisabled => 'Desativado';

  @override
  String panelScheduleNext(Object action, Object at) {
    return 'Próximo: $action às $at';
  }

  @override
  String get panelScheduleActionOpen => 'abrir';

  @override
  String get panelScheduleActionClose => 'fechar';

  @override
  String get panelAutoCloseIdle => 'Inativo';

  @override
  String get panelAutoCloseDisabled => 'Desativado';

  @override
  String get panelAutoCloseOffline =>
      'Automação offline — a regra não vai rodar';

  @override
  String panelAutoCloseClosingIn(int seconds) {
    return 'Fechando em ${seconds}s';
  }

  @override
  String get panelAutoCloseClosingNow => 'Fechando agora…';

  @override
  String get panelGridEmpty =>
      'Nenhum bloco ainda.\nToque em Adicionar bloco para colocar seus dispositivos aqui.';

  @override
  String get panelsOffline => 'Offline — mostrando os últimos valores';

  @override
  String get connectionConnecting => 'Conectando…';

  @override
  String get connectionReconnecting => 'Reconectando…';

  @override
  String get connectionShowingLastKnownValues =>
      'Mostrando os últimos valores conhecidos';

  @override
  String get connectionFailed => 'Falha na conexão';

  @override
  String get connectionAutomaticRetry =>
      'Novas tentativas automáticas vão continuar';

  @override
  String get connectionReconnectNow => 'Reconectar agora';

  @override
  String get settingsAbout => 'Sobre';

  @override
  String get settingsHelp => 'Ajuda e guia';

  @override
  String get settingsVersion => 'Versão';

  @override
  String get settingsRateApp => 'Avaliar o ZigDash';

  @override
  String get settingsRateAppSubtitle =>
      'Está gostando? Uma avaliação rápida ajuda outras pessoas a encontrá-lo.';

  @override
  String get settingsFeatureRequest => 'Sugerir um recurso';

  @override
  String get settingsFeatureRequestSubtitle =>
      'Conte o que deixaria o ZigDash melhor.';

  @override
  String get featureRequestGithub => 'No GitHub';

  @override
  String get featureRequestGithubSubtitle =>
      'Público: outras pessoas podem ver e votar.';

  @override
  String get featureRequestEmail => 'Por e-mail';

  @override
  String get featureRequestEmailSubtitle =>
      'Privado, direto para o desenvolvedor.';

  @override
  String get featureRequestEmailSubject => 'ZigDash: sugestão de recurso';

  @override
  String get featureRequestEmailPrompt =>
      'O que você gostaria que o ZigDash fizesse, e por quê?';

  @override
  String get settingsReportProblem => 'Relatar um problema';

  @override
  String get settingsReportProblemSubtitle =>
      'Algo quebrado ou confuso? Me conte.';

  @override
  String get reportProblemEmailSubject => 'ZigDash: relato de problema';

  @override
  String get reportProblemEmailPrompt =>
      'O que aconteceu e o que você esperava?';

  @override
  String get settingsBuyCoffee => 'Me pague um café';

  @override
  String get settingsBuyCoffeeSubtitle =>
      'Gratuito e de código aberto — as gorjetas mantêm o projeto vivo.';

  @override
  String get a11yBackupMenu => 'Backup e restauração';

  @override
  String get a11ySelectColor => 'Selecionar cor';

  @override
  String get a11ySelectIcon => 'Selecionar ícone';

  @override
  String get a11yDeleteOption => 'Excluir opção';

  @override
  String get a11yPanelOptions => 'Opções do bloco';

  @override
  String get a11yMoreOptions => 'Mais opções';

  @override
  String get a11yRefresh => 'Atualizar';

  @override
  String get a11yDeleteConnection => 'Excluir conexão';

  @override
  String get controlNotConnected => 'Sem conexão — alteração não enviada';

  @override
  String get discoverFromDevice => 'Adicionar de um dispositivo…';

  @override
  String get discoverFromDeviceSubtitle =>
      'Detectar automaticamente um dispositivo do Zigbee2MQTT';

  @override
  String get discoverTitle => 'Adicionar de um dispositivo';

  @override
  String get discoverBaseTopic => 'Tópico base do Zigbee2MQTT';

  @override
  String get discoverScanning => 'Procurando dispositivos…';

  @override
  String get discoverNone => 'Nenhum dispositivo encontrado.';

  @override
  String get discoverFailed =>
      'Nenhuma lista de dispositivos encontrada. Verifique o tópico base e se o broker está conectado.';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get previewTitle => 'Prévia ao vivo';

  @override
  String previewWaiting(Object topic) {
    return 'Aguardando uma mensagem em $topic…';
  }

  @override
  String previewExtracted(Object path, Object value) {
    return 'Extraído ($path): $value';
  }

  @override
  String get previewNoValue => '(sem valor neste caminho)';

  @override
  String get connErrorTitle => 'Erro de conexão';

  @override
  String get connErrorUnknown => 'Nenhum detalhe do erro disponível.';

  @override
  String get connTestButton => 'Testar conexão';

  @override
  String get connTestOk => 'Conexão bem-sucedida';

  @override
  String connTestFailed(Object error) {
    return 'Falha na conexão: $error';
  }

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get devicesAddButton => 'Adicionar dispositivo';

  @override
  String get devicesPairingTitle =>
      'Pareando — pressione o botão do dispositivo';

  @override
  String devicesPairingHint(int seconds) {
    return 'Procurando novos dispositivos… ${seconds}s';
  }

  @override
  String get devicesPairingStop => 'Parar';

  @override
  String get devicesNone => 'Nenhum dispositivo encontrado.';

  @override
  String get devicesListMissing =>
      'O Zigbee2MQTT não enviou a lista de dispositivos. Isso pode acontecer depois que o broker MQTT reinicia.';

  @override
  String get devicesRestartZ2m => 'Reiniciar o Zigbee2MQTT';

  @override
  String get devicesRestartingZ2m =>
      'Reiniciando o Zigbee2MQTT. Seus dispositivos devem aparecer em alguns segundos.';

  @override
  String get devicesBattery => 'Bateria';

  @override
  String get devicesLinkQuality => 'Link';

  @override
  String get devicesOnline => 'Online';

  @override
  String get devicesOffline => 'Offline';

  @override
  String devicesPaired(Object name) {
    return 'Pronto: $name';
  }

  @override
  String get devicesPairedHint =>
      'Adicionado à sua rede. Para colocá-lo em um painel, use \'Adicionar de um dispositivo\' nesse painel.';

  @override
  String get scenesTitle => 'Cenas';

  @override
  String get scenesNone =>
      'Nenhuma cena ainda. Deixe seus dispositivos do jeito que você gosta e salve-os como uma cena.';

  @override
  String get scenesNewButton => 'Nova cena';

  @override
  String scenesActivated(Object name) {
    return '$name ativada';
  }

  @override
  String get scenesActivateOffline =>
      'Sem conexão — não é possível ativar a cena';

  @override
  String get sceneFormNewTitle => 'Nova cena';

  @override
  String get sceneFormEditTitle => 'Editar cena';

  @override
  String get sceneFormNameLabel => 'Nome da cena';

  @override
  String get sceneFormDevicesHeader => 'Dispositivos a capturar';

  @override
  String get sceneFormCaptureHint =>
      'O estado ajustável atual de cada dispositivo selecionado (liga/desliga, brilho, cor, posição…) é salvo. Valores somente leitura são ignorados.';

  @override
  String get sceneFormNoDevices =>
      'Nenhum dispositivo controlável encontrado. Verifique se estão pareados e toque em atualizar.';

  @override
  String get sceneFormReadingState => 'Lendo o estado atual…';

  @override
  String get sceneCtrlPower => 'Energia';

  @override
  String get sceneCtrlBrightness => 'Brilho';

  @override
  String get sceneCtrlPosition => 'Posição';

  @override
  String sceneFormSelectedCount(int count) {
    return '$count selecionado(s)';
  }

  @override
  String get sceneFormNoDevicesSelected =>
      'Selecione pelo menos um dispositivo para capturar.';

  @override
  String get sceneFormNothingCaptured =>
      'Nada ajustável foi capturado dos dispositivos selecionados.';

  @override
  String get sceneDeleteTitle => 'Excluir cena?';

  @override
  String sceneDeleteMessage(Object name) {
    return '\"$name\" será removida. Os dispositivos mantêm o estado atual.';
  }

  @override
  String get sceneEditAction => 'Editar';

  @override
  String get sceneDeleteAction => 'Excluir';

  @override
  String get sceneAddToDashboard => 'Adicionar ao painel';

  @override
  String sceneAddedToDashboard(Object name) {
    return 'Adicionada a $name';
  }

  @override
  String sceneActionsCount(int count) {
    return '$count dispositivos';
  }

  @override
  String get scenesAllShutters => 'Todas as persianas';

  @override
  String get sceneCloseAllShutters => 'Fechar todas as persianas';

  @override
  String get sceneOpenAllShutters => 'Abrir todas as persianas';

  @override
  String get sceneStopAllShutters => 'Parar todas as persianas';

  @override
  String sceneShuttersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count persianas',
      one: '1 persiana',
    );
    return '$_temp0';
  }

  @override
  String get sceneWhichShutters => 'Quais persianas…';

  @override
  String get sceneWhichShuttersHint =>
      'Todas as persianas desta casa estão incluídas. Desmarque as que devem ficar de fora, como um portão de garagem.';

  @override
  String get scenesYours => 'As suas cenas';

  @override
  String get panelTypeScene => 'Cena';

  @override
  String get panelPickerSceneTitle => 'Botão de cena';

  @override
  String get panelPickerSceneSubtitle => 'Um toque ativa uma cena salva';

  @override
  String get panelSceneChoose => 'Cena';

  @override
  String get panelSceneMissing => 'Cena não encontrada — escolha de novo';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageDutch => 'Nederlands';

  @override
  String get languageSwedish => 'Svenska';

  @override
  String get languageNorwegian => 'Norsk';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageFrench => 'Français';

  @override
  String get guidedConnectTitle => 'Configure seu broker';

  @override
  String get guidedConnectIntro =>
      'Vamos testar cada etapa da conexão e mostrar seus dispositivos Zigbee.';

  @override
  String get guidedBaseTopic => 'Tópico base';

  @override
  String get guidedBaseTopicHint => 'zigbee2mqtt';

  @override
  String get guidedConnect => 'Testar e conectar';

  @override
  String get guidedTesting => 'Testando sua conexão…';

  @override
  String get stepResolve => 'Resolvendo o host';

  @override
  String get stepTcp => 'Conexão TCP';

  @override
  String get stepConnack => 'Handshake MQTT';

  @override
  String get stepAuth => 'Autenticação';

  @override
  String get stepDevices => 'Procurando dispositivos';

  @override
  String get diagResolveFail =>
      'Não foi possível resolver o nome do host. Verifique o endereço digitado.';

  @override
  String get diagResolveTimeout =>
      'A resolução do host expirou. Verifique o endereço e sua rede.';

  @override
  String get diagTcpFail =>
      'Não foi possível alcançar o broker. O Zigbee2MQTT está rodando? Verifique o endereço e a porta.';

  @override
  String get diagTcpTimeout =>
      'A conexão com o broker expirou. Ele pode estar offline ou inacessível.';

  @override
  String get diagConnackFail =>
      'O broker não concluiu o handshake MQTT. Verifique se é um broker MQTT (Mosquitto, Zigbee2MQTT).';

  @override
  String get diagAuthRejected =>
      'O broker rejeitou o usuário ou a senha. Verifique suas credenciais.';

  @override
  String get diagAuthRefused =>
      'O broker recusou a conexão. Verifique as configurações de conexão.';

  @override
  String foundDevices(Object count) {
    return '$count dispositivos encontrados';
  }

  @override
  String get foundDevicesHint =>
      'Seus dispositivos Zigbee estão visíveis. Continue para montar seu painel.';

  @override
  String get noDevicesTitle =>
      'Conectado — nenhum dispositivo encontrado ainda';

  @override
  String get noDevicesHint =>
      'O ZigDash vê seu broker, mas ainda não encontrou dispositivos Zigbee. Você pode iniciar o pareamento para adicioná-los.';

  @override
  String get startPairing => 'Iniciar pareamento';

  @override
  String get pairingEnabled =>
      'Pareamento ativado. Pressione o botão de pareamento do dispositivo para conectá-lo.';

  @override
  String get continueToDashboard => 'Continuar para o painel';

  @override
  String get guidedBackToForm => 'Editar configurações';

  @override
  String ladderTriedHint(Object count) {
    return '$count endereços testados';
  }

  @override
  String get guidedSaveFailed =>
      'Não foi possível salvar a conexão. Tente de novo.';

  @override
  String get setupWelcomeTitle => 'Boas-vindas ao ZigDash';

  @override
  String get setupWelcomeBody =>
      'O ZigDash controla sua casa Zigbee2MQTT existente — localmente, sem nuvem. Verifique se o Zigbee2MQTT está rodando e deixe o ZigDash encontrá-lo.';

  @override
  String get setupFindMySetup => 'Encontrar minha instalação';

  @override
  String get setupManualEntry => 'Inserir dados manualmente';

  @override
  String get setupScanningTitle => 'Procurando uma conexão…';

  @override
  String get setupScanningHint =>
      'Mantenha este dispositivo na mesma rede local que o host do Zigbee2MQTT.';

  @override
  String get setupCandidateFound => 'Possível conexão encontrada';

  @override
  String get setupNoCandidatesTitle => 'Nenhuma conexão encontrada';

  @override
  String get setupNoCandidatesBody => 'Onde o Zigbee2MQTT roda?';

  @override
  String get setupGuideHa =>
      'Home Assistant: verifique se o add-on do broker MQTT (ex.: Mosquitto) e o add-on do Zigbee2MQTT estão instalados e rodando.';

  @override
  String get setupGuidePi =>
      'Raspberry Pi / Linux: verifique se o broker (ex.: Mosquitto) e o serviço Zigbee2MQTT estão rodando e se a porta 1883 está acessível.';

  @override
  String get setupGuideSmlight =>
      'SMLIGHT / SMHUB: abra a interface web do dispositivo, vá em Settings > MQTT, ative Allow External para que o celular alcance o broker e verifique se o Zigbee2MQTT aparece como em execução.';

  @override
  String get setupTryAgain => 'Tentar de novo';

  @override
  String get setupAuthTitle => 'Este broker exige login';

  @override
  String setupAuthBody(Object host) {
    return 'Digite o usuário e a senha MQTT de $host.';
  }

  @override
  String get setupAuthRejectedBody =>
      'O usuário ou a senha foi rejeitado. Verifique e tente de novo.';

  @override
  String get setupAuthRejectedZ2m =>
      'O Zigbee2MQTT já inicia sessão neste broker: a página web dele mostra o utilizador em Definições › MQTT. Use esse utilizador e a respetiva senha.';

  @override
  String get setupAuthWhich =>
      'Este é o login MQTT, não a senha da página web do seu hub.';

  @override
  String get setupAuthHintHa =>
      'Home Assistant: use um usuário do Home Assistant. A maioria cria um só para MQTT em Configurações › Pessoas › Usuários, e o add-on Mosquitto o aceita.';

  @override
  String get setupAuthHintPi =>
      'Raspberry Pi ou Docker: o usuário e a senha do arquivo de senhas do Mosquitto, os mesmos do configuration.yaml do Zigbee2MQTT em mqtt.';

  @override
  String get setupAuthHintSmlight =>
      'SMLIGHT: o login exibido na página web do hub em Settings › MQTT.';

  @override
  String get setupVerifyingTitle => 'Verificando a conexão…';

  @override
  String get setupReviewTitle => 'Seus dispositivos';

  @override
  String setupReviewSubtitle(Object count) {
    return '$count dispositivos encontrados. Escolha o que vai para o seu primeiro painel.';
  }

  @override
  String setupCreateWithCount(Object count) {
    return 'Criar painel com $count';
  }

  @override
  String get setupGroupOther => 'Outros dispositivos';

  @override
  String get setupGroupUnsupported => 'Dispositivos sem suporte';

  @override
  String get setupCreatingTitle => 'Criando seu painel…';

  @override
  String get setupReadyTitle => 'Seu painel está pronto';

  @override
  String setupReadyBody(Object count) {
    return '$count controles criados.';
  }

  @override
  String get setupOpenDashboard => 'Abrir painel';

  @override
  String get setupErrUnreachableTitle =>
      'Não foi possível alcançar este endereço';

  @override
  String get setupErrUnreachableBody =>
      'Este dispositivo e o host do Zigbee2MQTT não se alcançam. Verifique se os dois estão na mesma rede local.';

  @override
  String get setupErrUnreachableAction => 'Tentar de novo';

  @override
  String get setupErrPortClosedTitle => 'Nada responde nesta porta';

  @override
  String get setupErrPortClosedBody =>
      'O host está acessível, mas nenhum broker MQTT respondeu. Verifique se o broker está rodando e se a porta está correta.';

  @override
  String get setupErrPortClosedAction => 'Tentar de novo';

  @override
  String get setupErrAuthRequiredTitle => 'Login obrigatório';

  @override
  String get setupErrAuthRequiredBody => 'Este broker exige usuário e senha.';

  @override
  String get setupErrAuthRequiredAction => 'Fazer login';

  @override
  String get setupErrAuthRejectedTitle => 'Login rejeitado';

  @override
  String get setupErrAuthRejectedBody => 'O broker rejeitou essas credenciais.';

  @override
  String get setupErrAuthRejectedAction => 'Tentar de novo';

  @override
  String get setupErrNotZ2mTitle => 'Nenhum Zigbee2MQTT aqui';

  @override
  String get setupErrNotZ2mBody =>
      'Um broker MQTT responde aqui, mas os tópicos do Zigbee2MQTT não foram encontrados. Pode ser outro broker.';

  @override
  String get setupErrNotZ2mAction => 'Escolher outro';

  @override
  String get setupErrNoDevicesTitle => 'Nenhum dispositivo recebido';

  @override
  String get setupErrNoDevicesBody =>
      'O Zigbee2MQTT está rodando, mas nenhum dispositivo foi publicado durante a verificação. Pareie os dispositivos no Zigbee2MQTT primeiro.';

  @override
  String get setupErrNoDevicesAction => 'Verificar de novo';

  @override
  String get setupErrScanFailedTitle => 'Sem rede local';

  @override
  String get setupErrScanFailedBody =>
      'Não foi possível identificar a rede local deste dispositivo. Conecte-se ao Wi-Fi e tente de novo.';

  @override
  String get setupErrScanFailedAction => 'Tentar de novo';

  @override
  String get setupErrSaveFailedTitle => 'Não foi possível salvar';

  @override
  String get setupErrSaveFailedBody =>
      'Falha ao salvar sua configuração. Nada ficou salvo pela metade — pode tentar de novo com segurança.';

  @override
  String get setupErrSaveFailedAction => 'Tentar de novo';

  @override
  String get setupErrUnknownTitle => 'Algo deu errado';

  @override
  String get setupErrUnknownBody => 'Ocorreu um erro inesperado.';

  @override
  String get setupErrUnknownAction => 'Tentar de novo';

  @override
  String get setupNoZ2mTitle =>
      'Seu broker funciona, mas o Zigbee2MQTT não está publicando aqui';

  @override
  String setupNoZ2mBody(String base) {
    return 'Escutamos em $base/bridge e não recebemos nada.';
  }

  @override
  String get setupBaseTopicQuestion => 'Usa outro tópico base?';

  @override
  String get setupGuidesTitle => 'Configurar o Zigbee2MQTT';

  @override
  String get setupTryDemoMeanwhile => 'Testar a demo enquanto isso';

  @override
  String get setupPlatformQuestion =>
      'Enquanto procuramos: onde corre o Zigbee2MQTT?';

  @override
  String get setupPlatformQuestionDone => 'Onde corre o Zigbee2MQTT?';

  @override
  String get setupScanDoneTitle => 'Escolha uma ligação';

  @override
  String get setupScanDoneHint =>
      'Respondeu mais de um broker. Escolha o que o Zigbee2MQTT usa.';

  @override
  String get setupPlatformHa => 'Home Assistant';

  @override
  String get setupPlatformSmlight => 'Hub SMLIGHT';

  @override
  String get setupPlatformPi => 'Raspberry Pi ou Docker';

  @override
  String get setupPlatformNotSure => 'Não sei';

  @override
  String setupScanProgress(int checked, int total) {
    return '$checked de $total endereços verificados';
  }

  @override
  String get setupScanHintHa =>
      'À procura do Home Assistant e do seu broker MQTT…';

  @override
  String get setupScanHintSmlight => 'À procura do seu hub SMLIGHT…';

  @override
  String get setupScanHintPi => 'À procura de um broker MQTT na sua rede…';

  @override
  String setupHubSeenHa(String host) {
    return 'Home Assistant encontrado em $host';
  }

  @override
  String setupHubSeenZ2m(String host) {
    return 'Zigbee2MQTT encontrado em $host';
  }

  @override
  String setupHubSeenSmlight(String host) {
    return 'O seu hub SMLIGHT foi encontrado em $host';
  }

  @override
  String get setupHubSeenHint => 'Ainda à procura do seu broker MQTT…';

  @override
  String get setupNoBrokerHaTitle =>
      'Home Assistant encontrado, mas sem broker MQTT';

  @override
  String setupNoBrokerHaBody(String host) {
    return 'O Home Assistant está em $host, mas nada responde na porta MQTT 1883. No Home Assistant, abra Definições › Add-ons, instale e inicie o add-on Mosquitto broker e tente novamente.';
  }

  @override
  String get setupNoBrokerHaZha =>
      'Usa o Zigbee próprio do Home Assistant (ZHA) em vez do Zigbee2MQTT? O ZigDash só funciona com o Zigbee2MQTT, então não enxerga dispositivos ZHA. A demonstração mostra o que você teria.';

  @override
  String get setupVpnHint =>
      'Há uma VPN ligada, e ela pode esconder sua rede de casa da busca. Se você estiver em casa, desligue a VPN e toque em Tentar de novo.';

  @override
  String get setupNoBrokerZ2mTitle =>
      'Zigbee2MQTT encontrado, mas o seu broker não está acessível';

  @override
  String setupNoBrokerZ2mBody(String host) {
    return 'O Zigbee2MQTT está em $host, mas o seu broker MQTT não aceita ligações do seu telemóvel. O Mosquitto 2 só escuta no próprio hub até a configuração ter \'listener 1883\' e \'allow_anonymous true\' (ou um login). Reinicie-o e tente novamente.';
  }

  @override
  String get setupNoBrokerSmlightTitle =>
      'Hub SMLIGHT encontrado, mas o MQTT está desligado';

  @override
  String setupNoBrokerSmlightBody(String host) {
    return 'O seu hub está em $host, mas o seu broker MQTT não está acessível. Na interface web do hub, abra Settings › MQTT, ative Allow External e verifique que o Zigbee2MQTT está a correr. Depois tente novamente.';
  }

  @override
  String get setupZ2mAsking => 'A perguntar ao Zigbee2MQTT onde está o broker…';

  @override
  String get setupZ2mLocalOnlyTitle =>
      'O seu broker só aceita ligações da própria máquina';

  @override
  String setupZ2mLocalOnlyBody(String server) {
    return 'O Zigbee2MQTT usa $server, e do seu telefone nada responde aí. O Mosquitto 2 faz isto por omissão. Adicione estas duas linhas ao mosquitto.conf, reinicie o Mosquitto e tente de novo:';
  }

  @override
  String get setupZ2mLocalOnlyNote =>
      'Prefere um login em vez de acesso aberto? Use um password_file em vez de allow_anonymous.';

  @override
  String setupZ2mUnreachable(String server) {
    return 'O Zigbee2MQTT usa o broker em $server, mas ele não respondeu ao seu telefone. Verifique se o broker está a correr e se o telefone está na mesma rede.';
  }

  @override
  String setupConnectTo(String host) {
    return 'Ligar a $host';
  }

  @override
  String get setupNotFoundHa =>
      'Nenhum Home Assistant encontrado nesta rede. Confira se o celular está no mesmo Wi-Fi que o Home Assistant (não uma rede de convidados) e tente de novo. Se souber o endereço, digite-o abaixo.';

  @override
  String get setupNotFoundSmlight =>
      'Nenhum hub SMLIGHT encontrado nesta rede. Confira se o hub está ligado e o celular no mesmo Wi-Fi, e tente de novo. Se souber o endereço, digite-o abaixo.';

  @override
  String get setupNotFoundPi =>
      'Nenhum broker MQTT encontrado nesta rede. Verifique que o Mosquitto está a correr e a escutar na rede (porta 1883) e que o seu telemóvel está no mesmo Wi-Fi. Depois tente novamente.';

  @override
  String get setupAddressQuestionHa => 'Onde você abre o Home Assistant?';

  @override
  String get setupAddressQuestionSmlight =>
      'Qual é o endereço do seu hub SMLIGHT?';

  @override
  String get setupAddressQuestionPi =>
      'Qual é o endereço da máquina que roda o Mosquitto?';

  @override
  String get setupAddressQuestionAny =>
      'Qual é o endereço do seu hub, ou da máquina que roda o Zigbee2MQTT?';

  @override
  String get setupAddressHint =>
      'Um endereço como 192.168.1.20, um nome ou o link do seu navegador';

  @override
  String get setupAddressCheck => 'Verificar este endereço';

  @override
  String setupAddressNothing(String host) {
    return 'Nada respondeu em $host. Confira o endereço e se o celular está no mesmo Wi-Fi.';
  }

  @override
  String setupAddressNotResolved(String host) {
    return 'Não foi possível resolver $host. Nomes terminados em .local costumam falhar no Android; tente o endereço IP. O Home Assistant o mostra em Configurações › Sistema › Rede.';
  }

  @override
  String setupAddressNotLocal(String host) {
    return '$host não está na sua rede doméstica. Use o endereço que funciona no seu Wi-Fi, não um link remoto como Nabu Casa ou DuckDNS.';
  }

  @override
  String get setupAddressInvalid => 'Digite um endereço primeiro.';

  @override
  String guidedHostYourPhone(String ip, String prefix) {
    return 'O seu telemóvel é $ip, por isso o hub costuma começar por $prefix.';
  }

  @override
  String get guidedHostHa =>
      'Usa o Home Assistant? O host é o endereço com que abre o Home Assistant, porta 1883.';

  @override
  String get demoBannerText => 'Você está no modo demo';

  @override
  String get demoBannerAction => 'Conectar sua casa';

  @override
  String get deviceOn => 'Ligado';

  @override
  String get deviceOff => 'Desligado';

  @override
  String get deviceOpen => 'Aberto';

  @override
  String get deviceClosed => 'Fechado';

  @override
  String get deviceMotion => 'Movimento';

  @override
  String get deviceClear => 'Livre';

  @override
  String get deviceLeakDetected => 'Vazamento detectado';

  @override
  String get deviceSmokeDetected => 'Fumaça detectada';

  @override
  String get deviceGasDetected => 'Gás detectado';

  @override
  String get deviceWaiting => 'Aguardando o primeiro relatório';

  @override
  String deviceEndpointsOnOff(int on, int off) {
    return '$on ligados · $off desligados';
  }

  @override
  String get deviceBrightness => 'Brilho';

  @override
  String get deviceWhite => 'Branco';

  @override
  String get deviceColor => 'Cor';

  @override
  String get deviceHue => 'Matiz';

  @override
  String get devicePosition => 'Posição';

  @override
  String get deviceControls => 'Controles';

  @override
  String deviceBattery(int percent) {
    return 'Bateria $percent%';
  }

  @override
  String get deviceToggle => 'Ligar ou desligar';

  @override
  String get deviceMore => 'Mais';

  @override
  String get sectionLights => 'Luzes';

  @override
  String get sectionSwitchesCovers => 'Interruptores e persianas';

  @override
  String get sectionSensors => 'Sensores';

  @override
  String get sectionOther => 'Outros';

  @override
  String get homeFirstName => 'Minha casa';

  @override
  String homeNumberedName(int number) {
    return 'Casa $number';
  }

  @override
  String get dashAddTile => 'Adicionar bloco';

  @override
  String get addTileSearch => 'Pesquisar dispositivos';

  @override
  String get addTileNotOnDashboard => 'Fora de painéis';

  @override
  String get addTileAllDevices => 'Todos os dispositivos';

  @override
  String get addTileReading => 'Leitura';

  @override
  String get addTileReadingSubtitle => 'Um valor de um dispositivo ou tópico';

  @override
  String get readingShowAs => 'Mostrar como';

  @override
  String get readingStyleValue => 'Valor';

  @override
  String get readingStyleGauge => 'Medidor';

  @override
  String get gaugeBands => 'Faixas de cor';

  @override
  String get gaugeBandsHelper =>
      'Até três. A faixa em que o valor está colore o arco.';

  @override
  String get gaugeBandFrom => 'De';

  @override
  String get gaugeBandTo => 'Até';

  @override
  String get gaugeBandAdd => 'Adicionar faixa';

  @override
  String get gaugeBandRemove => 'Remover faixa';

  @override
  String get gaugeToneNormal => 'Normal';

  @override
  String get gaugeToneGood => 'Bom';

  @override
  String get gaugeToneAttention => 'Atenção';

  @override
  String get addTileCustom => 'Bloco MQTT personalizado';

  @override
  String get addTileCustomSubtitle =>
      'Qualquer tipo de bloco, configurado por tópico';

  @override
  String get addTileNoDevices =>
      'Nenhum dispositivo para mostrar. Conecte-se ao seu broker ou pareie um dispositivo no Zigbee2MQTT.';

  @override
  String get addTileAdd => 'Adicionar';

  @override
  String get addTileName => 'Nome';

  @override
  String addTileNameHint(String model) {
    return 'ex.: $model';
  }

  @override
  String get addTileSection => 'Seção';

  @override
  String get addTileNoSection => 'Sem seção';

  @override
  String get addTileSize => 'Tamanho';

  @override
  String get deviceClassColorLight => 'Luz colorida';

  @override
  String get deviceClassLight => 'Luz';

  @override
  String get deviceClassSwitch => 'Interruptor ou tomada';

  @override
  String get deviceClassCover => 'Persiana';

  @override
  String get deviceClassLeak => 'Vazamento ou fumaça';

  @override
  String get deviceClassContact => 'Contato';

  @override
  String get deviceClassMotion => 'Movimento';

  @override
  String get deviceClassClimate => 'Sensor de clima';

  @override
  String get deviceClassGeneric => 'Dispositivo';

  @override
  String get deviceNotResponding => 'Sem resposta';

  @override
  String get homeAdd => 'Adicionar uma casa';

  @override
  String get homeManage => 'Gerenciar casas';

  @override
  String get homeSwitch => 'Trocar de casa';

  @override
  String get navDevices => 'Dispositivos';

  @override
  String get navScenes => 'Cenas';

  @override
  String get devicesNewDot => 'Novos dispositivos';

  @override
  String get editEditing => 'Editando';

  @override
  String get editDashboard => 'Painel';

  @override
  String get editDone => 'Concluir';

  @override
  String get editAddSection => 'Adicionar seção';

  @override
  String get editSectionName => 'Nome da seção';

  @override
  String get editRenameSection => 'Renomear seção';

  @override
  String get editDeleteSection => 'Excluir seção';

  @override
  String get editDeleteSectionBody => 'O que fazer com os blocos dela?';

  @override
  String get editKeepTiles => 'Manter blocos, remover seção';

  @override
  String get editDeleteTiles => 'Excluir os blocos também';

  @override
  String get editMoveToSection => 'Mover para a seção';

  @override
  String get editEditTile => 'Editar bloco';

  @override
  String get editRemove => 'Remover do painel';

  @override
  String get editRemoved => 'Bloco removido';

  @override
  String get editUndo => 'Desfazer';

  @override
  String get editReplaceWithDevice => 'Substituir por bloco de dispositivo';

  @override
  String get editMoveEarlier => 'Mover para antes';

  @override
  String get editMoveLater => 'Mover para depois';

  @override
  String editUnassigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dispositivos não estão em nenhum painel',
      one: '1 dispositivo não está em nenhum painel',
    );
    return '$_temp0';
  }

  @override
  String get editTileActions => 'Opções do bloco';

  @override
  String get editSave => 'Salvar';

  @override
  String get editCancel => 'Cancelar';

  @override
  String get ageJustNow => 'Agora mesmo';

  @override
  String ageMinutes(int n) {
    return 'há $n min';
  }

  @override
  String ageHours(int n) {
    return 'há $n h';
  }

  @override
  String get statusCantReach => 'Não foi possível alcançar seu broker';

  @override
  String get statusWhy => 'Por quê?';

  @override
  String get statusWhyTitle => 'Seu broker não está respondendo';

  @override
  String get statusWhyBody =>
      'O ZigDash continua tentando sozinho. Até ele voltar, os blocos mostram os últimos valores conhecidos, esmaecidos e com a idade. Verifique se o broker está ligado e se este celular está na mesma rede, ou teste a conexão nas configurações dela.';

  @override
  String get statusSettings => 'Configurações de conexão';

  @override
  String get deviceAddToDashboard => 'Adicionar a um painel';

  @override
  String get deviceDismiss => 'Dispensar';

  @override
  String get devicesFilterAll => 'Todos';

  @override
  String devicesFilterAttention(int count) {
    return 'Precisa de atenção · $count';
  }

  @override
  String devicesFilterUnassigned(int count) {
    return 'Fora de painéis · $count';
  }

  @override
  String get devicesNoMatch => 'Nenhum dispositivo corresponde';

  @override
  String get deviceBatteryLow => 'Bateria fraca';

  @override
  String get deviceLinkWeak => 'Fraco';

  @override
  String get deviceUnsupported => 'Sem suporte no Zigbee2MQTT';

  @override
  String get deviceInterviewFailed => 'O pareamento não terminou';

  @override
  String get deviceNoReport => 'Nenhum relatório ainda';

  @override
  String get devicesAvailabilityOff =>
      'A disponibilidade do Zigbee2MQTT está desativada, então dispositivos offline aparecem como Sem resposta.';

  @override
  String get devicesAvailabilityHow => 'Como ativar';

  @override
  String get devicesDotBattery => 'Bateria fraca';

  @override
  String get deviceDetails => 'Detalhes do dispositivo';

  @override
  String get deviceGone => 'Este dispositivo não está mais no Zigbee2MQTT.';

  @override
  String get deviceControlTitle => 'Controle';

  @override
  String get deviceReadingsTitle => 'Leituras';

  @override
  String get deviceHealthTitle => 'Saúde';

  @override
  String get deviceOnDashboards => 'Nos painéis';

  @override
  String get deviceUnsupportedBody =>
      'O Zigbee2MQTT ainda não oferece suporte a este dispositivo, então não há nada para controlar.';

  @override
  String get deviceAddReadingTile => 'Adicionar como bloco de leitura';

  @override
  String get deviceAddReadingTo => 'Adicionar a qual painel?';

  @override
  String deviceAddedTo(Object dashboard) {
    return 'Adicionado a $dashboard';
  }

  @override
  String get deviceLinkQuality => 'Qualidade do link';

  @override
  String get deviceLinkGood => 'Bom';

  @override
  String get devicePowerSource => 'Fonte de energia';

  @override
  String get devicePowerBattery => 'Bateria';

  @override
  String get devicePowerMains => 'Rede elétrica';

  @override
  String get deviceLastHeard => 'Último contato';

  @override
  String get deviceAvailability => 'Disponibilidade';

  @override
  String get deviceAvailabilityOff => 'Desativada no Zigbee2MQTT';

  @override
  String get settingsPrivacy => 'Política de privacidade';

  @override
  String get settingsPrivacySubtitle =>
      'Sem telemetria. Tudo fica neste celular.';

  @override
  String get homeCurrent => 'Casa atual';

  @override
  String get homeConnection => 'Conexão';

  @override
  String get homeSwitchTo => 'Mudar para esta casa';

  @override
  String get homeDelete => 'Excluir casa';

  @override
  String get devicesSelect => 'Selecione um dispositivo';

  @override
  String get scenesSelect => 'Selecione uma cena para editar';

  @override
  String get panelFormTopic => 'Tópico';

  @override
  String get panelFormPickDevice => 'Escolher um dispositivo';

  @override
  String get panelFormStateTopic => 'Tópico de estado';

  @override
  String get panelFormCommandTopic => 'Tópico de comando';

  @override
  String get panelFormCommandTopicDerived =>
      'Preenchido a partir do tópico de estado até você alterá-lo.';

  @override
  String panelFormLinkedTo(Object device) {
    return 'Vinculado a $device';
  }

  @override
  String get panelFormOpenDevice => 'Abrir dispositivo';

  @override
  String get panelFormUnlink => 'Desvincular';

  @override
  String get panelFormValueChoices => 'Valores deste dispositivo';

  @override
  String get panelFormAdvanced => 'Avançado';

  @override
  String get panelFormAdvancedSubtitle => 'Substituir prefixo, QoS, retain';

  @override
  String get panelFormStateTopicHelper =>
      'Em branco = o próprio prefixo (o estado de um dispositivo do Zigbee2MQTT).';

  @override
  String get dashWallDisplay => 'Tela de parede';

  @override
  String get analyticsSetupCheckbox =>
      'Compartilhar dados de uso anônimos para melhorar a configuração';

  @override
  String get analyticsWhatsShared => 'O que é compartilhado';

  @override
  String get analyticsCardTitle => 'Ajudar a melhorar o ZigDash?';

  @override
  String get analyticsCardBody =>
      'Compartilhe dados de uso anônimos: quais etapas da configuração falham e quais recursos são usados. Nunca seus dispositivos, tópicos ou broker.';

  @override
  String get analyticsShare => 'Compartilhar';

  @override
  String get analyticsNoThanks => 'Não, obrigado';

  @override
  String get settingsAnalytics => 'Compartilhar dados de uso anônimos';

  @override
  String get settingsAnalyticsSubtitle =>
      'Etapas da configuração e recursos usados. Nunca seus dispositivos, tópicos ou broker.';

  @override
  String get settingsPrivacySubtitleOptIn =>
      'Dados de uso anônimos. Desative no botão acima.';

  @override
  String get dashDefaultName => 'Casa';

  @override
  String get dashExportSaveFile => 'Salvar arquivo';

  @override
  String get dashExportSaved => 'Backup salvo';

  @override
  String get dashImportChooseFile => 'Escolher arquivo';

  @override
  String get dashImportFileUnreadable => 'Não foi possível ler o arquivo';

  @override
  String get getHelpTitle => 'Obter ajuda';

  @override
  String get getHelpTryFirst => 'Tente isto primeiro';

  @override
  String get getHelpPromise =>
      'Ainda não funcionou? Costumo responder em até 3 dias, em inglês ou hebraico. Nunca vou pedir suas senhas.';

  @override
  String get getHelpIncluded => 'O que vai junto';

  @override
  String get getHelpContact => 'Falar com o suporte';

  @override
  String get getHelpCopy => 'Copiar detalhes';

  @override
  String get getHelpCopied => 'Detalhes copiados';

  @override
  String get getHelpLink => 'Ainda não funcionou? Obter ajuda';

  @override
  String get getHelpEmailSubject => 'ZigDash: ajuda para fazer funcionar';

  @override
  String get getHelpEmailPrompt =>
      'O que você estava tentando fazer e o que aconteceu?';

  @override
  String get settingsHelpSupport => 'Ajuda e suporte';

  @override
  String get settingsGetHelp => 'Obter ajuda';

  @override
  String get settingsGetHelpSubtitle =>
      'Não está funcionando? Primeiro dicas, depois contato';

  @override
  String get settingsCommunity => 'Entre na comunidade ZigDash';

  @override
  String get settingsCommunitySubtitle =>
      'Grupo no Telegram: dúvidas, ideias e novidades';

  @override
  String get getHelpCommunity => 'Perguntar no grupo do Telegram';

  @override
  String get demoBannerHelp => 'Obter ajuda';

  @override
  String get tipSameWifiTitle => 'Mesmo Wi-Fi do hub';

  @override
  String get tipSameWifiBody =>
      'Seu celular precisa estar na mesma rede do hub, não em uma rede de convidados. Desligue os dados móveis durante a configuração.';

  @override
  String get tipBrokerRunningTitle => 'O broker está rodando';

  @override
  String get tipBrokerRunningBody =>
      'Home Assistant: o add-on Mosquitto está iniciado. Raspberry Pi: o Mosquitto está rodando. SMLIGHT: Settings › MQTT está ativado.';

  @override
  String get tipBrokerAcceptsTitle => 'O broker aceita seu celular';

  @override
  String get tipBrokerAcceptsBody =>
      'SMLIGHT: ative Allow External. O Mosquitto 2 só aceita conexões do próprio hub até ser configurado para escutar na rede (porta 1883).';

  @override
  String get tipMeshTitle => 'Wi-Fi mesh ou dois roteadores?';

  @override
  String get tipMeshBody =>
      'Se o hub estiver ligado a um segundo roteador, seu celular talvez não o encontre. Ligue o hub ao roteador principal ou conecte pelo endereço dele.';

  @override
  String get tipByAddressTitle => 'Conectar pelo endereço';

  @override
  String get tipByAddressBody =>
      'Encontre o endereço do hub no app do seu roteador e depois toque em \"Inserir dados manualmente\".';

  @override
  String get tipSameNetworkTitle => 'Mesma rede';

  @override
  String get tipSameNetworkBody =>
      'O celular e o hub precisam estar no mesmo Wi-Fi. Desligue os dados móveis.';

  @override
  String get tipAddressChangedTitle => 'O endereço mudou';

  @override
  String get tipAddressChangedBody =>
      'Hubs podem receber um novo endereço depois de reiniciar. Confira no app do seu roteador e reserve o endereço lá para que ele não mude.';

  @override
  String get tipRightPortTitle => 'A porta certa';

  @override
  String get tipRightPortBody =>
      'O MQTT costuma usar a 1883 (8883 com TLS). 8080 ou 80 é a interface web do hub, não o MQTT.';

  @override
  String get tipStartBrokerTitle => 'O broker está rodando';

  @override
  String get tipStartBrokerBody =>
      'Inicie o Mosquitto ou o add-on do broker e tente de novo.';

  @override
  String get tipMosquitto2Title => 'Mosquitto 2';

  @override
  String get tipMosquitto2Body =>
      'O Mosquitto 2 só aceita conexões do próprio hub até ser configurado para escutar na rede (porta 1883).';

  @override
  String get tipMqttLoginTitle => 'O login do MQTT, não o login web';

  @override
  String get tipMqttLoginBody =>
      'A senha da interface web do hub geralmente não é a do MQTT. Home Assistant: use um usuário do Home Assistant ou o login definido no add-on Mosquitto.';

  @override
  String get tipSpacesTitle => 'Verifique os espaços';

  @override
  String get tipSpacesBody =>
      'Ao copiar uma senha, pode vir um espaço no final.';

  @override
  String get tipZ2mBrokerTitle => 'O Zigbee2MQTT usa este broker';

  @override
  String get tipZ2mBrokerBody =>
      'Nas configurações do Zigbee2MQTT, verifique se o servidor MQTT dele é este mesmo broker.';

  @override
  String get tipBaseTopicTitle => 'Tópico base';

  @override
  String get tipBaseTopicBody =>
      'Se você mudou o tópico base de \"zigbee2mqtt\", informe-o na configuração manual.';

  @override
  String get tipPairFirstTitle => 'Pareie os dispositivos primeiro';

  @override
  String get tipPairFirstBody =>
      'Abra a interface web do Zigbee2MQTT e pareie pelo menos um dispositivo, depois verifique de novo.';

  @override
  String get tipRestartZ2mTitle => 'Reiniciar o Zigbee2MQTT';

  @override
  String get tipRestartZ2mBody =>
      'Se os dispositivos estão pareados mas nenhum aparece, reinicie o Zigbee2MQTT para que ele publique a lista de dispositivos.';

  @override
  String get tipNumberAddressTitle => 'Use o endereço numérico';

  @override
  String get tipNumberAddressBody =>
      'Nomes terminados em .local não funcionam em todo celular Android. Tente o endereço numérico do hub, como 192.168.1.20.';

  @override
  String get tipPortProtocolTitle => 'Porta e protocolo';

  @override
  String get tipPortProtocolBody =>
      'O normal é TCP na 1883. Escolha TLS ou WebSocket só se o seu broker estiver configurado para isso.';

  @override
  String get tipManualLoginTitle => 'Login';

  @override
  String get tipManualLoginBody =>
      'Deixe usuário e senha em branco se o seu broker não tiver. Caso contrário, use o login do MQTT, não o login da interface web do hub.';

  @override
  String get tipHubOnTitle => 'O hub está ligado?';

  @override
  String get tipHubOnBody =>
      'Uma queda de energia ou uma atualização pode tê-lo reiniciado. Espere um minuto depois que ele voltar.';

  @override
  String get tipAwayTitle => 'Você está em casa?';

  @override
  String get tipAwayBody =>
      'Fora de casa, o app precisa de um endereço remoto (por exemplo, Tailscale). Defina-o nas configurações de conexão da casa.';

  @override
  String get tipTailscaleIpTitle => 'Use o IP do Tailscale, não o nome';

  @override
  String get tipTailscaleIpBody =>
      'Nomes terminados em .ts.net muitas vezes não são resolvidos dentro de apps. Abra o app Tailscale no celular e confira se está conectado; depois use o endereço 100.x.y.z do hub como host remoto.';

  @override
  String get tipHomeAddressChangedTitle => 'O endereço mudou?';

  @override
  String get tipHomeAddressChangedBody =>
      'Depois que o roteador reinicia, o hub pode receber um novo endereço. Reserve o endereço dele no app do roteador e depois atualize a casa.';

  @override
  String get tipRestartZ2mButtonTitle => 'Reiniciar o Zigbee2MQTT';

  @override
  String get tipRestartZ2mButtonBody =>
      'Se o broker reiniciou, a lista de dispositivos do Zigbee2MQTT some até o Zigbee2MQTT reiniciar. Use o botão \"Reiniciar o Zigbee2MQTT\" na aba \"Dispositivos\".';

  @override
  String get tipZ2mRunningTitle => 'O Zigbee2MQTT está rodando?';

  @override
  String get tipZ2mRunningBody =>
      'Abra a interface web dele. Se não carregar, reinicie o Zigbee2MQTT no seu hub.';

  @override
  String get tipCantConnectTitle => 'Não consigo conectar ao meu hub';

  @override
  String get tipCantConnectBody =>
      'Mesmo Wi-Fi, broker rodando, Allow External ou Mosquitto escutando na rede e, então, conecte pelo endereço.';

  @override
  String get tipDeviceWrongTitle =>
      'Um dispositivo aparece errado ou não responde';

  @override
  String get tipDeviceWrongBody =>
      'Primeiro verifique-o na interface web do Zigbee2MQTT. Se lá funcionar, use \"Relatar um problema\".';

  @override
  String get tipHowDoITitle => 'Como faço…';

  @override
  String get tipHowDoIBody =>
      'Cenas, Tela de parede, agendamentos e backups estão em \"Ajuda e guia\".';

  @override
  String get tipRenameHomeTitle => 'Renomear uma casa';

  @override
  String get tipRenameHomeBody =>
      'Uma casa com o nome do endereço? Configurações › Casas, toque na casa e depois em Nome.';

  @override
  String get tipWhatYouNeedTitle => 'O que você precisa';

  @override
  String get tipWhatYouNeedBody =>
      'Um broker MQTT (Mosquitto) e o Zigbee2MQTT rodando em um hub: Home Assistant, um Raspberry Pi ou um hub SMLIGHT.';

  @override
  String get tipSetupAtHomeTitle => 'No mesmo Wi-Fi';

  @override
  String get tipSetupAtHomeBody =>
      'Configure em casa, com o celular no mesmo Wi-Fi do hub.';

  @override
  String get tipFindSetupTitle => 'Depois';

  @override
  String get tipFindSetupBody =>
      'Saia da demo e toque em \"Encontrar minha instalação\". O ZigDash procura seu hub sozinho.';

  @override
  String getHelpNoEmailApp(Object email) {
    return 'Nenhum app de e-mail encontrado. Copie os detalhes e escreva para $email.';
  }

  @override
  String get shortcutWorking => 'executando…';

  @override
  String get shortcutCantReach => 'Não foi possível alcançar sua casa';

  @override
  String get shortcutNotConfirmed => 'Não confirmado';

  @override
  String get shortcutRemoved => 'Removido';

  @override
  String get shortcutSceneSent => 'Enviada';

  @override
  String get shortcutSceneConfirmed => 'Confirmada';

  @override
  String get shortcutChooseDevice => 'Escolha um dispositivo';

  @override
  String get shortcutChooseScene => 'Escolha uma cena';

  @override
  String get shortcutOpenAppFirstScene =>
      'Abra o ZigDash e crie uma cena primeiro.';

  @override
  String get shortcutChooseGroup => 'Escolha um grupo';

  @override
  String get shortcutPickDevices => 'Escolher dispositivos…';

  @override
  String get shortcutGroupName => 'Nome do grupo';

  @override
  String get shortcutGroupLimit => 'Até 5 dispositivos e 3 cenas';

  @override
  String get shortcutAddTile => 'Adicionar às Configurações rápidas';

  @override
  String get shortcutAddShortcut => 'Adicionar atalho';

  @override
  String get shortcutAddToHome => 'Adicionar à tela inicial';

  @override
  String get shortcutWidgetHowToTitle => 'Adicionar o widget';

  @override
  String get shortcutWidgetHowTo =>
      'Toque e segure um espaço vazio da tela inicial, toque em Widgets, encontre o ZigDash e arraste o widget desejado.';

  @override
  String shortcutTileReady(Object name, Object slot) {
    return '$name está no bloco ZigDash $slot das Configurações rápidas';
  }

  @override
  String shortcutTileAlready(Object name, Object slot) {
    return '$name já está no bloco ZigDash $slot';
  }

  @override
  String get shortcutTileHowToTitle => 'Adicionar o bloco';

  @override
  String shortcutTileHowTo(Object slot) {
    return 'Abra as Configurações rápidas (deslize para baixo duas vezes), toque no lápis para editar e arraste \"ZigDash $slot\" para seus blocos.';
  }

  @override
  String shortcutPickTitle(Object slot) {
    return 'Escolha um dispositivo para ZigDash $slot';
  }

  @override
  String get shortcutPickEmpty =>
      'Ainda não há dispositivos para ligar. Coloque primeiro uma luz, tomada ou persiana em um painel.';

  @override
  String get shortcutSlotsFull =>
      'Os 4 blocos do ZigDash estão em uso. Qual deve mostrar este dispositivo no lugar?';

  @override
  String shortcutSlotLabel(Object slot) {
    return 'ZigDash $slot';
  }

  @override
  String get shortcutSlotEmpty => 'Não usado';

  @override
  String get deviceRename => 'Renomear';

  @override
  String get deviceRenameTitle => 'Renomear dispositivo';

  @override
  String get deviceRenameHint =>
      'Um nome para o cômodo ou o dispositivo, como Quarto';

  @override
  String deviceRenamed(Object name) {
    return 'Renomeado para $name';
  }

  @override
  String deviceRenameFailed(Object reason) {
    return 'Não foi possível renomear: $reason';
  }

  @override
  String get deviceRenameNoAnswer => 'O Zigbee2MQTT não respondeu';

  @override
  String get shortcutOpenAppFirst =>
      'Abra o ZigDash e coloque primeiro um dispositivo em um painel.';

  @override
  String get pollTitle => 'O que o ZigDash deve fazer a seguir?';

  @override
  String get pollBody =>
      'Escolha o que você mais usaria. A resposta é enviada com seus dados de uso anônimos.';

  @override
  String get pollNotifications => 'Notificações';

  @override
  String get pollHistory => 'Gráficos de histórico';

  @override
  String get pollKiosk => 'Modo quiosque para um tablet na parede';

  @override
  String get pollGroups => 'Grupos Zigbee';

  @override
  String get pollNotNow => 'Agora não';

  @override
  String get pollThanks => 'Obrigado! Isso ajuda a decidir o que vem a seguir.';

  @override
  String get pollNoAnalytics =>
      'Os dados de uso estão desativados, então nada é enviado daqui. Conte para nós em Sugerir um recurso.';

  @override
  String alertLeak(Object name) {
    return '💧 Vazamento — $name';
  }

  @override
  String alertLeakCleared(Object name) {
    return '✅ $name está seco de novo';
  }

  @override
  String alertSmoke(Object name) {
    return '🔥 Fumaça — $name';
  }

  @override
  String alertSmokeCleared(Object name) {
    return '✅ Sem fumaça em $name';
  }

  @override
  String alertOpened(Object name) {
    return '🚪 $name aberto';
  }

  @override
  String alertBattery(Object name, Object value) {
    return '🔋 Bateria fraca — $name, $value%';
  }

  @override
  String get alertTest => 'Notificação de teste do ZigDash';

  @override
  String get alertsChannel => 'Alertas';

  @override
  String get alertsChannelDescription => 'Vazamentos e fumaça';

  @override
  String get noticesChannel => 'Avisos';

  @override
  String get noticesChannelDescription => 'Portas, janelas e baterias';

  @override
  String get alertsTitle => 'Alertas';

  @override
  String get alertsStatusOn => 'Os alertas estão ativos';

  @override
  String get alertsStatusPaused =>
      'Alertas pausados: o Node-RED no hub não está rodando';

  @override
  String get alertsStatusNotSetUp => 'Não configurado';

  @override
  String get alertsStatusPhoneOff => 'Este celular não recebe notificações';

  @override
  String get alertsIntro =>
      'Receba uma notificação neste celular quando houver vazamento, fumaça, uma porta aberta ou bateria fraca, mesmo com o ZigDash fechado. O Node-RED no seu hub vigia os dispositivos; o ZigDash o configura.';

  @override
  String get alertsSetUpHub => 'Configurar alertas no hub';

  @override
  String get alertsHubInstalled => 'O fluxo de alertas está instalado no hub';

  @override
  String get alertsHubUpdated => 'O fluxo de alertas no hub está atualizado';

  @override
  String get alertsHubNeedsLogin =>
      'O Node-RED pede login, então importe o fluxo manualmente:';

  @override
  String get alertsHubManualSteps =>
      'Abra o Node-RED no hub, escolha Importar, cole o fluxo copiado, escolha seu broker no nó do broker e clique em Deploy.';

  @override
  String get alertsCopyFlow => 'Copiar o fluxo';

  @override
  String get alertsFlowCopied => 'Fluxo copiado';

  @override
  String alertsNoNodeRed(Object host) {
    return 'Os alertas precisam do Node-RED no hub, e nada responde na porta 1880 em $host. Em um SMLIGHT SMHUB, instale-o em Apps.';
  }

  @override
  String get alertsHubFailed => 'O Node-RED recusou o fluxo';

  @override
  String get alertsRecent => 'Alertas recentes';

  @override
  String get alertsRecentNone => 'Nada ainda';

  @override
  String get alertsYourAlerts => 'Seus alertas';

  @override
  String get alertsAdd => 'Adicionar alerta';

  @override
  String get alertsNotificationsOnThisPhone => 'Notificações neste celular';

  @override
  String get alertsNoGoogle =>
      'Este celular não tem serviços do Google, então o ZigDash não pode receber pushes aqui.';

  @override
  String get alertsSendTest => 'Enviar notificação de teste';

  @override
  String get alertsTestSent => 'Teste enviado. Deve chegar agora.';

  @override
  String alertsTestFailed(Object status) {
    return 'O hub não conseguiu enviar ($status)';
  }

  @override
  String get alertsTestTimedOut =>
      'Sem resposta do hub. O fluxo de alertas está rodando?';

  @override
  String get alertsNotConnected => 'Sem conexão com o hub';

  @override
  String get alertsTurnOff => 'Desligar os alertas';

  @override
  String get alertsTurnOffBody =>
      'Os alertas param em todos os celulares desta casa.';

  @override
  String get alertKindLeak => 'Vazamento';

  @override
  String get alertKindSmoke => 'Fumaça';

  @override
  String get alertKindOpened => 'Porta ou janela aberta';

  @override
  String get alertKindBattery => 'Bateria fraca';

  @override
  String get alertsEditTitle => 'Alerta';

  @override
  String get alertsKind => 'O quê';

  @override
  String get alertsDevices => 'Dispositivos';

  @override
  String get alertsNoDevicesForKind =>
      'Nenhum dispositivo desta casa informa isso.';

  @override
  String get alertsHours => 'Só entre';

  @override
  String get alertsHoursAny => 'A qualquer hora';

  @override
  String get alertsHoursFrom => 'De';

  @override
  String get alertsHoursTo => 'Até';

  @override
  String get alertsThreshold => 'Bateria abaixo de';

  @override
  String get alertsDelete => 'Excluir alerta';

  @override
  String get alertsNotifyMe => 'Me avisar…';

  @override
  String get alertsWhatLeaves =>
      'Os alertas para o ZigDash são criptografados de ponta a ponta: o serviço push do Google os transporta, mas não consegue lê-los. Nada mais sai do seu hub.';

  @override
  String get alertsRestricted =>
      'O Android pode parar o ZigDash em segundo plano, e as notificações podem atrasar ou se perder. Permita a execução em segundo plano nas configurações do Android (na Samsung: Bateria › Apps que nunca dormem).';

  @override
  String get alertsOpenSettings => 'Abrir configurações do Android';

  @override
  String get alertsOff => 'Desligado';

  @override
  String get alertsSuggested => 'Alertas sugeridos';

  @override
  String alertsSuggestedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dispositivos',
      one: '1 dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get alertsTurnOn => 'Ativar';

  @override
  String get alertsShare => 'Compartilhar alertas';

  @override
  String get alertsShareBody =>
      'Quem tiver este link recebe os alertas desta casa no app ntfy, sem precisar do ZigDash. O texto do alerta passa pelo ntfy.sh sem criptografia.';

  @override
  String get alertsShareLink => 'Link';

  @override
  String get alertsShareNewLink => 'Novo link';

  @override
  String get alertsShareCopied => 'Link copiado';

  @override
  String get alertsShareOff => 'Parar de compartilhar';

  @override
  String get alertsGetWithNtfy => 'Receber notificações com o ntfy';

  @override
  String get alertsPushover => 'Pushover';

  @override
  String get alertsPushoverBody =>
      'Alertas de fumaça e vazamento se repetem até serem confirmados. Precisa de uma conta Pushover (US\$ 4,99 uma vez após o teste); as chaves ficam no seu broker.';

  @override
  String get alertsPushoverUser => 'Chave de usuário';

  @override
  String get alertsPushoverToken => 'Token do app';

  @override
  String get alertsHideNames => 'Ocultar nomes dos dispositivos';

  @override
  String get alertsNtfyServer => 'Servidor ntfy';

  @override
  String get wallSheetTitle => 'Tela de parede';

  @override
  String get wallSheetSubtitle => 'Para um tablet na parede.';

  @override
  String get wallKeepOn => 'Manter a tela ligada e ocultar as barras';

  @override
  String get wallKeepOnSubtitle =>
      'Elas voltam ao tocar e somem de novo após 10 segundos.';

  @override
  String get wallFullscreen => 'Tela cheia';

  @override
  String get wallFullscreenSubtitle =>
      'Oculta também as barras de status e de navegação do Android.';

  @override
  String get wallDimAfter => 'Escurecer após';

  @override
  String get wallDimOff => 'Desligado';

  @override
  String wallDimMinutes(Object minutes) {
    return '$minutes min';
  }

  @override
  String get kioskLock => 'Bloqueio de quiosque';

  @override
  String get kioskLockSubtitle =>
      'Só os painéis desta casa e seus controles continuam acessíveis. Segure o título para sair.';

  @override
  String get kioskPin => 'PIN';

  @override
  String get kioskPinSet => 'Definir';

  @override
  String get kioskPinNotSet => 'Não definido';

  @override
  String get kioskPinChange => 'Alterar';

  @override
  String get kioskPinRemove => 'Remover';

  @override
  String get kioskPinSetTitle => 'Definir um PIN';

  @override
  String get kioskPinEnterTitle => 'Digite o PIN';

  @override
  String get kioskPinHint => '4 dígitos';

  @override
  String get kioskPinConfirmHint => 'De novo';

  @override
  String get kioskPinMismatch => 'Os dois PINs são diferentes.';

  @override
  String get kioskPinWrong => 'PIN incorreto.';

  @override
  String get kioskPinForgot => 'Esqueceu o PIN?';

  @override
  String get kioskPinForgotBody =>
      'Um PIN esquecido só pode ser redefinido apagando os dados do ZigDash nas configurações do Android, o que remove esta casa a menos que você tenha um backup. Exporte um antes de definir o PIN.';

  @override
  String get kioskExportBackup => 'Exportar backup';

  @override
  String get kioskOsPin => 'Fixar o ZigDash também no Android';

  @override
  String get kioskOsPinSubtitle =>
      'O Android bloqueia o botão Início e os apps recentes até o ZigDash ser desafixado. Um tablet sem tela de bloqueio desafixa com um gesto, então isto não é o bloqueio.';

  @override
  String get kioskOn => 'Quiosque ligado. Segure o título para sair.';

  @override
  String get kioskLeaveTitle => 'Sair do quiosque?';

  @override
  String get kioskLeave => 'Sair';

  @override
  String get kioskStay => 'Ficar';

  @override
  String get a11yKioskLeave => 'Segure para sair do quiosque';

  @override
  String get historyTitle => 'Histórico';

  @override
  String get historyRangeDay => '24 horas';

  @override
  String get historyRangeWeek => '7 dias';

  @override
  String get historyRangeMonth => '30 dias';

  @override
  String get historySetupTitle => 'Grave o histórico no seu hub';

  @override
  String get historySetupBody =>
      'O ZigDash não tem servidor, então um pequeno fluxo do Node-RED no seu hub grava a cada 15 minutos os números dos seus painéis. Ele guarda 30 dias, no seu próprio broker.';

  @override
  String get historySetupAction => 'Configurar no hub';

  @override
  String get historyInstalled =>
      'Gravando. Os primeiros valores aparecem em até 15 minutos.';

  @override
  String historyNoNodeRed(String host) {
    return 'O histórico precisa do Node-RED no hub, e nada responde na porta 1880 em $host. Num SMLIGHT SMHUB, instale-o em Apps.';
  }

  @override
  String historyRecordingSince(String date) {
    return 'Gravando desde $date';
  }

  @override
  String get historyEmpty =>
      'Ainda sem valores. O gravador salva a cada 15 minutos.';

  @override
  String get historyRecorderOffline =>
      'O gravador no hub não está respondendo, então valores recentes podem faltar.';

  @override
  String get historyLocked =>
      'Histórico mais longo faz parte do ZigDash Pro, uma compra única.';

  @override
  String get historyUnlock => 'Desbloquear';

  @override
  String get proTitle => 'ZigDash Pro';

  @override
  String get proAbout => 'Histórico de 7 e 30 dias. Uma compra única.';

  @override
  String get proUnlocked => 'Desbloqueado. Obrigado por apoiar o ZigDash.';

  @override
  String get historyNotRecorded =>
      'Só são gravados os números que aparecem num painel. Adicione este como bloco para começar o histórico.';

  @override
  String historyNeedsPassword(String host) {
    return 'Mais um passo: seu broker pede login. Abra o Node-RED em $host:1880, clique duas vezes em \"ZigDash history broker\", digite a senha MQTT na aba Security e clique em Deploy. O ZigDash nunca envia sua senha ao hub.';
  }

  @override
  String get historyNotConnected =>
      'O gravador está instalado mas não se conectou ao broker. Se o broker pede login, digite a senha no nó \"ZigDash history broker\" do Node-RED e clique em Deploy.';

  @override
  String get historyPersistence =>
      'O histórico fica no seu broker. Se você roda o Mosquitto por conta própria, confira se a configuração tem \"persistence true\", senão o histórico se perde quando o broker reinicia.';
}
