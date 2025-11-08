import 'package:flutter/material.dart';
import '../call/call_payload.dart';
import '../call/agora_controller.dart';
import '../driver_api.dart'; // для AppApi

class CallInProgressScreen extends StatefulWidget {
  final CallPayload payload;
  const CallInProgressScreen({super.key, required this.payload});

  static Route route(CallPayload p) => MaterialPageRoute(
     settings: const RouteSettings(name: 'CallInProgressScreen'),
     builder: (_) => CallInProgressScreen(payload: p),
  );

  @override
  State<CallInProgressScreen> createState() => _CallInProgressScreenState();
}

class _CallInProgressScreenState extends State<CallInProgressScreen> {
  @override
  void dispose() {
    AgoraController.instance.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On call')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await DriverApi.endCall({'call_id': widget.payload.callId, 'reason': 'hangup'});
            if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          child: const Text('Hang up'),
        ),
      ),
    );
  }
}
