// AI 伴读相关数据模型。
// 包含：对话消息、摘要结果等。

/// 消息角色枚举 — 区分用户消息和 AI 回复
enum AiMessageRole {
  user,       // 用户发送的消息
  assistant,  // AI 助手的回复
  system,     // 系统提示（不展示给用户）
}

/// AI 对话消息模型
class AiMessage {
  AiMessage({
    required this.id,
    required this.content,
    required this.role,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id; // 消息唯一标识
  final AiMessageRole role; // 发送者角色
  final DateTime timestamp; // 消息时间戳
  String content; // 消息内容（支持 Markdown）
  bool isStreaming; // 是否正在流式生成中
  bool isError; // 是否为错误消息

  /// 生成唯一 ID 的辅助方法
  static String generateId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
}

/// AI 摘要结果模型
class AiSummary {
  const AiSummary({
    required this.summary,
    required this.keyPoints,
    this.keywords = const [],
  });

  final String summary; // 核心摘要文本
  final List<String> keyPoints; // 关键要点列表
  final List<String> keywords; // 关键词标签
}
