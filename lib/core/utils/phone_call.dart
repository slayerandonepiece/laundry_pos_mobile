import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the dialer for [phone]. On devices that cannot place calls
/// (iPad, simulator) the number is copied to the clipboard instead,
/// so the button never silently does nothing.
Future<void> callPhone(BuildContext context, String phone) async {
  final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: clean));
  } catch (_) {
    opened = false;
  }
  if (opened) return;

  await Clipboard.setData(ClipboardData(text: clean));
  messenger?.showSnackBar(
    SnackBar(content: Text('Calls aren\'t available here. $clean copied.')),
  );
}
