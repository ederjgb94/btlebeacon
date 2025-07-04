import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Beacon Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Escáner de Beacons BLE'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _uidController = TextEditingController();
  final List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  String _status = 'Listo para escanear';

  @override
  void initState() {
    super.initState();
    // Poner el UID predeterminado
    _uidController.text = 'FDA50693A4E24FB1AFCFC6EB07647825';
  }

  Future<void> _requestPermissions() async {
    // Para iOS, verificar permisos específicos
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();

      if (statuses[Permission.bluetooth]!.isDenied ||
          statuses[Permission.locationWhenInUse]!.isDenied) {
        setState(() {
          _status =
              'Permisos necesarios denegados. Ve a Configuración > Privacidad';
        });
        return;
      }
    } else {
      // Para Android
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothScan]!.isDenied ||
          statuses[Permission.bluetoothConnect]!.isDenied ||
          statuses[Permission.location]!.isDenied) {
        setState(() {
          _status = 'Permisos de Bluetooth denegados';
        });
        return;
      }
    }
  }

  Future<void> _discover() async {
    await _requestPermissions();

    if (await FlutterBluePlus.isSupported == false) {
      setState(() {
        _status = 'Bluetooth no disponible en este dispositivo';
      });
      return;
    }

    // Verificar el estado del adaptador Bluetooth
    BluetoothAdapterState adapterState =
        await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() {
        _status = 'Por favor, activa el Bluetooth';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _devices.clear();
      _status = 'Escaneando dispositivos BLE...';
    });

    String targetUid = _uidController.text.toUpperCase();

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          String deviceId = result.device.remoteId.str.toUpperCase();
          String deviceName = result.device.platformName;

          // Debug: mostrar todos los dispositivos encontrados
          print('Dispositivo encontrado: $deviceName ($deviceId)');
          print('RSSI: ${result.rssi}');
          print(
            'Manufacturer Data: ${result.advertisementData.manufacturerData}',
          );

          bool deviceFound = false;

          // Buscar en los datos de advertising (manufacturer data)
          for (var entry in result.advertisementData.manufacturerData.entries) {
            String hexData = entry.value
                .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                .join('')
                .toUpperCase();
            print('Manufacturer ${entry.key}: $hexData');

            if (hexData.contains(targetUid)) {
              deviceFound = true;
              break;
            }
          }

          // Buscar en service data
          for (var entry in result.advertisementData.serviceData.entries) {
            String hexData = entry.value
                .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                .join('')
                .toUpperCase();
            print('Service ${entry.key}: $hexData');

            if (hexData.contains(targetUid)) {
              deviceFound = true;
              break;
            }
          }

          // Buscar en el nombre del dispositivo
          if (deviceName.toUpperCase().contains(targetUid)) {
            deviceFound = true;
          }

          // Buscar en el deviceId
          if (deviceId.contains(targetUid) || targetUid.contains(deviceId)) {
            deviceFound = true;
          }

          if (deviceFound && !_devices.contains(result.device)) {
            setState(() {
              _devices.add(result.device);
              _status =
                  'Dispositivo encontrado: $deviceName ($deviceId) - RSSI: ${result.rssi}';
            });
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [], // Escanear todos los servicios
        withNames: [], // Escanear todos los nombres
        continuousUpdates: true, // Actualizaciones continuas
      );

      // Esperar a que termine el escaneo
      await Future.delayed(const Duration(seconds: 15));

      if (_devices.isEmpty) {
        setState(() {
          _status =
              'No se encontraron dispositivos con el UID especificado.\nAsegúrate de que el beacon esté cerca y transmitiendo.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error al escanear: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
      await _scanSubscription?.cancel();
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _status = 'Conectando a ${device.platformName}...';
      });

      await device.connect();

      setState(() {
        _status = 'Conectado exitosamente a ${device.platformName}';
      });

      // Descubrir servicios
      List<BluetoothService> services = await device.discoverServices();

      setState(() {
        _status = 'Conectado. Servicios encontrados: ${services.length}';
      });

      // Mostrar información de servicios
      for (BluetoothService service in services) {
        print('Servicio: ${service.uuid}');
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          print('  Característica: ${characteristic.uuid}');
        }
      }
    } catch (e) {
      setState(() {
        _status = 'Error al conectar: $e';
      });
    }
  }

  @override
  void dispose() {
    _uidController.dispose();
    _scanSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextField(
                controller: _uidController,
                decoration: const InputDecoration(
                  labelText: 'UID',
                  border: OutlineInputBorder(),
                  hintText: 'Ingrese el UID del dispositivo BLE',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isScanning ? null : _discover,
                child: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Descubrir'),
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_devices.isNotEmpty) ...[
                const Text(
                  'Dispositivos encontrados:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return Card(
                        child: ExpansionTile(
                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Dispositivo BLE',
                          ),
                          subtitle: Text('ID: ${device.remoteId.str}'),
                          leading: const Icon(Icons.bluetooth),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ID completo: ${device.remoteId.str}'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Estado: ${device.isConnected ? "Conectado" : "Desconectado"}',
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => _connectToDevice(device),
                                    child: const Text('Conectar'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
