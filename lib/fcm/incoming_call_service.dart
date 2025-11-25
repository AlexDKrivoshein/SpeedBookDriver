// lib/fcm/incoming_call_service.dart
import 'dart:async';

class CallEndInfo {
  final int callId;
  final String reason; // e.g. 'remote_hangup', 'caller_cancelled', 'declined', 'timeout'
  CallEndInfo(this.callId, {this.reason = 'remote_hangup'});
}

class IncomingCallService {
  static final _acceptedStream = StreamController<int>.broadcast();
  static Stream<int> get acceptedStream => _acceptedStream.stream;

  static void markCallAccepted(int callId) {
    _acceptedStream.add(callId);
  }

  static final _endedStream = StreamController<CallEndInfo>.broadcast();
  static Stream<CallEndInfo> get endedStream => _endedStream.stream;
  static void markCallEnded(int callId, {String reason = 'remote_hangup'}) {
    _endedStream.add(CallEndInfo(callId, reason: reason));
  }
}