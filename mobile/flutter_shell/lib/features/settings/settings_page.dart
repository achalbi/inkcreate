import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const <Widget>[
          ListTile(
            title: Text('Web shell'),
            subtitle: Text(
              'The main InkCreate experience remains in the WebView.',
            ),
          ),
          ListTile(
            title: Text('Native capabilities'),
            subtitle: Text(
              'Native routes are exposed to the web app through capability discovery.',
            ),
          ),
          ListTile(
            title: Text('Privacy'),
            subtitle: Text(
              'Classic ML Kit routes run on-device. Android GenAI routes are gated by device readiness.',
            ),
          ),
        ],
      ),
    );
  }
}
