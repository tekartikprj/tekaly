// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:sembast/sembast_io.dart';
import 'models.dart';
import 'package:path/path.dart';
import 'package:tekartik_firebase_local/firebase_local.dart';

var apps = CvCollectionReference<FsApp>('apps');
var infos = apps.any.collection<CvFirestoreDocument>('infos');
var appInfo1Ref = infos.cast<FsAppInfo>().doc('app');
var noNameAppInfo1Ref = infos.cast<FsNoNameAppInfo>().doc('noNameApp');
late Firestore firestore;

Future<void> main() async {
  await run();
}

Future<void> run() async {
  WidgetsFlutterBinding.ensureInitialized();
  initFsBuilders();
  var sembastFactory = kIsWeb
      ? databaseFactoryWeb
      : createDatabaseFactoryIo(
          rootPath: normalize(
            absolute('.local', 'tk_firestore_explorer_test_app'),
          ),
        );
  firestore = newFirestoreServiceSembast(
    databaseFactory: sembastFactory,
  ).firestore(newFirebaseAppLocal());
  //.debugQuickLoggerWrapper();
  var app1 = apps.doc('app1').cv()..name.v = 'test';
  await firestore.cvSet(app1);
  documentViewAddTypeNames({
    FsApp: 'FsApp',
    FsAppInfo: 'FsAppInfo',
    CvAppInfoSub1: 'CvAppInfoSub1',
    CvAppInfoSub2: 'CvAppInfoSub2',
  });
  documentViewAddCollections([apps, infos]);
  documentViewAddDocuments([
    apps.doc('app1'),
    apps.doc('app2'),
    appInfo1Ref,
    noNameAppInfo1Ref,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
      body: ListView(
        children: [
          ListTile(
            title: const Text('Firestore root'),
            onTap: () async {
              await goToFsDocumentRootScreen(context, firestore: firestore);
            },
          ),
          ListTile(
            title: const Text('apps'),
            onTap: () async {
              await goToFsDocumentListScreen(
                context,
                firestore: firestore,
                query: apps.query(),
              );
            },
          ),
          ListTile(
            title: const Text('apps/app1'),
            onTap: () async {
              await goToFsDocumentViewScreen(
                context,
                firestore: firestore,
                doc: apps.doc('app1'),
              );
            },
          ),
        ],
      ),
    );
  }
}
