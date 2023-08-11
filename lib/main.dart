import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';

//TODO: replace this with your bucket
const bucket = 'gs://cast-tube.appspot.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterBackgroundService().configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      autoStartOnBoot: false,
      initialNotificationContent: 'Uploading...',
      initialNotificationTitle: 'Uploading',
    ),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  FlutterBackgroundService().startService();
                },
                child: const Text('Start'),
              ),
              TextButton(
                onPressed: () async {
                  setState(() {});
                  final appFolder = await getExternalStorageDirectory();
                  // TODO: replace with target file for uploading
                  final filePath = '${appFolder!.absolute.path}/app-tester.apk';
                  FlutterBackgroundService().invoke(
                    'upload',
                    {
                      'file': filePath,
                    },
                  );
                },
                child: const Text('Upload'),
              ),
              TextButton(
                onPressed: () {
                  FlutterBackgroundService().invoke('stop');
                },
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance serviceInstance) async {
  print('started');
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.signInAnonymously();
  final storage = FirebaseStorage.instanceFor(bucket: bucket);

  serviceInstance.on('upload').listen((event) async {
    print('upload');
    final file = File(event!['file'] as String);
    final randomValue = DateTime.now().millisecondsSinceEpoch;
    final uploadTask = storage.ref('$randomValue').putFile(file);
    uploadTask.snapshotEvents.map((task) {
      switch (task.state) {
        case TaskState.paused:
        case TaskState.running:
          return 100.0 * (task.bytesTransferred / task.totalBytes);
        case TaskState.success:
          return 100;
        case TaskState.canceled:
        case TaskState.error:
          return -1;
      }
    }).listen(
      (event) {
        print('progress: $event');
        if (event == 100) serviceInstance.stopSelf();
      },
      cancelOnError: true,
    );
  });

  serviceInstance.on('stop').listen((event) {
    print('stop');
    serviceInstance.stopSelf();
  });

  Timer.periodic(
    const Duration(seconds: 1),
    (timer) {
      print('${timer.tick}: Background service alive');
    },
  );
}
