import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<PackageInfo> _packageInfo() => PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: _packageInfo(),
        builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
          final PackageInfo? info = snapshot.data;

          return ListView(
            children: <Widget>[
              const ListTile(
                title: Text('InkCreate mobile shell'),
                subtitle: Text(
                  'Incremental hybrid shell around the existing Rails product.',
                ),
              ),
              ListTile(
                title: const Text('Version'),
                subtitle: Text(
                  info == null
                      ? 'Loading…'
                      : '${info.version} (${info.buildNumber})',
                ),
              ),
              const ListTile(
                title: Text('Store review note'),
                subtitle: Text(
                  'The app provides native scanning, offline awareness, permissions UX, settings, and about pages beyond a thin wrapper.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
