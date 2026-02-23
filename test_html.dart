import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

void main() async {
  final res = await http.get(Uri.parse('https://wp.nishiki.tech/wp-json/wp/v2/posts?_embed&per_page=5'));
  final data = jsonDecode(res.body);
  final post = data.firstWhere((p) => p['title']['rendered'].toString().contains('Day 18'), orElse: () => data[0]);
  
  final content = post['content']['rendered'].toString();
  stdout.writeln('HTML contains table? ${content.contains('<table')}');
  final tableStart = content.indexOf('<table');
  if (tableStart != -1) {
    stdout.writeln(content.substring(tableStart, tableStart + 1000));
  }
}
