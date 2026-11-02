import 'package:flutter/material.dart';

/// Lightweight markdown helpers for the note editor and note previews.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});
}

/// Removes the most common markdown markers so list previews stay readable.
String stripMarkdown(String input) {
  var text = input;
  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  text = text.replaceAll(RegExp(r'`([^`]*)`'), r'$1');
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
  text = text.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  text = text.replaceAll(
    RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s*', multiLine: true),
    '',
  );
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'(\*\*|__)(.*?)\1'), r'$2');
  text = text.replaceAll(RegExp(r'(\*|_)(.*?)\1'), r'$2');
  text = text.replaceAll(RegExp(r'~~(.*?)~~'), r'$1');
  text = text.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text.trim();
}
