import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme/mesh_theme.dart';
import 'services/identity_service.dart';
import 'services/routing_service.dart';
import 'services/transport_bluetooth.dart';
import 'services/transport_wifi_direct.dart';
import 'services/permission_service.dart';
import 'services/contact_service.dart';
import 'services/room_service.dart';
import 'services/geo_service.dart';
import 'services/message_store.dart';
import 'services/backup_service.dart';
import 'services/phonebook_service.dart';
import 'services/power_mode.dart';
import 'services/foreground_service.dart';
import 'services/dialogs_service.dart';
import 'services/local_notify.dart';
import 'ui/home_screen.dart';

class BridgeMeshApp extends StatefulWidget {
  const BridgeMeshApp({super.key});

  @override
  State<BridgeMeshApp> createState() => _BridgeMeshAppState();
}

class _BridgeMeshAppState extends State<BridgeMeshApp> {
  late final IdentityService _identity;
  late final PermissionService _perms;
  late final BluetoothTransport _bt;
  late final WifiDirectTransport _wifi;
  late final GeoService _geo;
  late final ContactService _contacts;
  late final RoomService _rooms;
  late final MessageStore _store;
  late final BackupService _backup;
  late final PhoneBookService _phonebook;
  late final PowerModeService _power;
  late final DialogsService _dialogs;
  late final RoutingService _routing;

  @override
  void initState() {
    super.initState();
    _identity = IdentityService();
    _perms = PermissionService();
    _power = PowerModeService();
    _bt = BluetoothTransport();
    _wifi = WifiDirectTransport();
    _geo = GeoService();
    _phonebook = PhoneBookService();
    _contacts = ContactService(_identity);
    _contacts.bindPhoneBook(_phonebook);
    _rooms = RoomService(_identity, _geo);
    _store = MessageStore(_identity);
    _dialogs = DialogsService(_identity);
    _backup = BackupService(
      identity: _identity,
      contacts: _contacts,
      rooms: _rooms,
    );
    _routing = RoutingService(
      identity: _identity,
      contacts: _contacts,
      rooms: _rooms,
      geo: _geo,
      store: _store,
      dialogs: _dialogs,
    );
    _routing.attachBluetooth(_bt);
    _routing.attachWifi(_wifi);

    // Загружаем данные ДО запуска, чтобы isOnboarded() вернул
    // правильное значение сразу при первом build.
    _boot();
  }

  Future<void> _boot() async {
    await LocalNotify.init();
    await Future.wait<void>([
      _identity.load(),
      _contacts.load(),
      _rooms.load(),
      _store.load(),
      _phonebook.load(),
      _power.load(),
      _dialogs.load(),
    ]);
    _applyPowerMode();
    if (!mounted) return;
    setState(() {});
    _routing.start();

    // Не даём системе убить mesh, пока приложение работает.
    // Когда приложение свернуто — foreground-сервис держит процесс
    // и показывает уведомление в шторке.
    await ForegroundService.start();
  }

  @override
  void dispose() {
    // Не останавливаем сервис тут — он живёт вместе с процессом.
    _routing.stop();
    super.dispose();
  }

  void _applyPowerMode() {
    _bt.applyPowerMode(_power.mode);
    _wifi.applyPowerMode(_power.mode);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return MaterialApp(
      title: 'BridgeMesh',
      debugShowCheckedModeBanner: false,
      theme: MeshTheme.light(),
      darkTheme: MeshTheme.dark(),
      themeMode: ThemeMode.dark,
      home: HomeScreen(
        identity: _identity,
        permissions: _perms,
        routing: _routing,
        bluetooth: _bt,
        wifi: _wifi,
        contacts: _contacts,
        rooms: _rooms,
        geo: _geo,
        store: _store,
        backup: _backup,
        power: _power,
        dialogs: _dialogs,
      ),
    );
  }
}
